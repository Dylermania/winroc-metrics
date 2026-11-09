import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../core/constants.dart';
import '../../core/security.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/daos/attendance_dao.dart';
import '../../data/daos/finance_dao.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';
import '../communication/reminders.dart';

final _usersProvider =
    StreamProvider<List<User>>((ref) => ref.watch(adminDaoProvider).watchUsers());
final _termsProvider =
    StreamProvider<List<Term>>((ref) => ref.watch(adminDaoProvider).watchTerms());
final _activityProvider =
    StreamProvider<List<ActivityLog>>((ref) => ref.watch(adminDaoProvider).watchActivity());
final _leviesProvider =
    StreamProvider<List<Levy>>((ref) => ref.watch(financeDaoProvider).watchLevies());
final _activeMembersProvider = FutureProvider<List<Member>>(
    (ref) => ref.watch(memberDaoProvider).activeMembers());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = (user?.role ?? ClubRole.member).can(Capability.admin);
    final items = <(IconData, String, Widget, bool)>[
      (Icons.tune, S.general, const _GeneralSettingsScreen(), isAdmin),
      (Icons.calendar_month, S.academicCalendar, const _CalendarScreen(), isAdmin),
      (Icons.restart_alt, S.resetForNewTerm, const _ResetTermScreen(), isAdmin),
      (Icons.school, S.promote, const _PromotionScreen(), isAdmin),
      (Icons.manage_accounts, S.usersAccounts, const _UsersScreen(), isAdmin),
      (Icons.category, S.categories, const _CategoriesScreen(), isAdmin),
      (Icons.backup, S.backup, const _BackupScreen(), isAdmin),
      (Icons.history, S.activityLog, const _ActivityScreen(), isAdmin),
      (Icons.info_outline, S.helpAbout, const _AboutScreen(), true),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: ListView(children: [
        for (final (icon, label, screen, allowed) in items)
          if (allowed)
            ListTile(
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => screen)),
            ),
      ]),
    );
  }
}

class _GeneralSettingsScreen extends ConsumerStatefulWidget {
  const _GeneralSettingsScreen();

  @override
  ConsumerState<_GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<_GeneralSettingsScreen> {
  final _school = TextEditingController();
  final _device = TextEditingController();
  final _grace = TextEditingController();
  final _threshold = TextEditingController();
  final _autoLock = TextEditingController();
  final _lateFine = TextEditingController();
  String _theme = 'system';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    _school.text = await db.setting('school_name', fallback: Defaults.schoolName);
    _device.text = await db.setting('device_name', fallback: Platform.localHostname);
    _grace.text = await db.setting('grace_minutes', fallback: '${Defaults.graceMinutes}');
    _threshold.text =
        await db.setting('attendance_threshold', fallback: '${Defaults.attendanceThreshold}');
    _autoLock.text = await db.setting('auto_lock_minutes', fallback: '${Defaults.autoLockMinutes}');
    final fine = int.tryParse(await db.setting('late_fine_pesewas', fallback: '0')) ?? 0;
    _lateFine.text = (fine / 100).toStringAsFixed(2);
    _theme = await db.setting('theme', fallback: 'system');
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_school, _device, _grace, _threshold, _autoLock, _lateFine]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final grace = int.tryParse(_grace.text.trim());
    final threshold = int.tryParse(_threshold.text.trim());
    final autoLock = int.tryParse(_autoLock.text.trim());
    final fine = parseGhs(_lateFine.text.trim());
    if (grace == null || threshold == null || autoLock == null || fine < 0 ||
        threshold < 1 || threshold > 100 || autoLock < 1 || grace < 0) {
      showSnack(context, 'Enter valid numbers (attendance 1-100, auto-lock at least 1).');
      return;
    }
    final db = ref.read(databaseProvider);
    await db.setSetting('school_name', _school.text.trim().isEmpty ? Defaults.schoolName : _school.text.trim());
    await db.setSetting('device_name', _device.text.trim().isEmpty ? Platform.localHostname : _device.text.trim());
    await db.setSetting('grace_minutes', '$grace');
    await db.setSetting('attendance_threshold', '$threshold');
    await db.setSetting('auto_lock_minutes', '$autoLock');
    await db.setSetting('late_fine_pesewas', '$fine');
    await db.setSetting('theme', _theme);
    await db.audit('update_settings', 'settings', 'general');
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, S.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.general)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                    controller: _school,
                    decoration: const InputDecoration(labelText: 'School name')),
                const SizedBox(height: 16),
                TextField(
                    controller: _device,
                    decoration: const InputDecoration(
                        labelText: 'This device name (shown during sync)')),
                const SizedBox(height: 16),
                TextField(
                    controller: _grace,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: S.gracePeriod)),
                const SizedBox(height: 16),
                TextField(
                    controller: _threshold,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: S.attendanceThreshold)),
                const SizedBox(height: 16),
                TextField(
                    controller: _autoLock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: S.autoLock)),
                const SizedBox(height: 16),
                TextField(
                    controller: _lateFine,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: S.lateFine)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _theme,
                  decoration: const InputDecoration(labelText: S.theme),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text(S.themeSystem)),
                    DropdownMenuItem(value: 'light', child: Text(S.themeLight)),
                    DropdownMenuItem(value: 'dark', child: Text(S.themeDark)),
                  ],
                  onChanged: (v) => setState(() => _theme = v ?? 'system'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: _save, icon: const Icon(Icons.save), label: const Text(S.save)),
              ],
            ),
    );
  }
}

class _CalendarScreen extends ConsumerWidget {
  const _CalendarScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(_termsProvider);
    final year = ref.watch(currentYearProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text(S.academicCalendar)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader('${S.academicYears}${year != null ? ' - ${year.name}' : ''}'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(year?.name ?? 'No current year'),
              subtitle: year == null ? null : Text('${fmtDate(year.startDate)} to ${fmtDate(year.endDate)}'),
              trailing: TextButton(
                onPressed: () => _newYearDialog(context, ref),
                child: const Text(S.newYear),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(S.terms),
          terms.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (list) => Column(children: [
              for (final t in list)
                Card(
                  child: ListTile(
                    leading: Icon(t.isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: t.isCurrent ? Theme.of(context).colorScheme.primary : null),
                    title: Text('Term ${t.number}${t.isCurrent ? ' (${S.current})' : ''}'),
                    subtitle: Text('${fmtDate(t.startDate)} to ${fmtDate(t.endDate)}'),
                    trailing: t.isCurrent
                        ? null
                        : TextButton(
                            onPressed: () async {
                              await ref.read(adminDaoProvider).setCurrentTerm(t.id);
                              if (context.mounted) showSnack(context, S.saved);
                            },
                            child: const Text(S.setCurrent),
                          ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _PeriodsScreen(term: t))),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: year == null ? null : () => _newTermDialog(context, ref, year, list),
                icon: const Icon(Icons.add),
                label: const Text(S.newTerm),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Tap a term to manage its ${S.vacationPeriods.toLowerCase()}. Sessions on those dates are flagged.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _newYearDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final now = DateTime.now();
    String? start = dateOnly(DateTime(now.year, 9, 1));
    String? end = dateOnly(DateTime(now.year + 1, 7, 31));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text(S.newYear),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. 2027/2028)')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.from}: ${start == null ? '-' : fmtDate(start!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: start);
              if (d != null) setS(() => start = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.to}: ${end == null ? '-' : fmtDate(end!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: end);
              if (d != null) setS(() => end = d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      )),
    );
    if (ok == true && name.text.trim().isNotEmpty && start != null && end != null) {
      final id = newId();
      await ref.read(adminDaoProvider).saveYear(
          AcademicYearsCompanion(
              id: Value(id),
              name: Value(name.text.trim()),
              startDate: Value(start!),
              endDate: Value(end!),
              createdAt: Value(nowIso()),
              updatedAt: Value(nowIso())),
          id,
          isNew: true);
      if (context.mounted) showSnack(context, S.saved);
    }
    name.dispose();
  }

  Future<void> _newTermDialog(BuildContext context, WidgetRef ref, AcademicYear year, List<Term> existing) async {
    final number = TextEditingController(text: '${existing.where((t) => t.academicYearId == year.id).length + 1}');
    String? start;
    String? end;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text(S.newTerm),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Term number')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.from}: ${start == null ? '-' : fmtDate(start!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: start);
              if (d != null) setS(() => start = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.to}: ${end == null ? '-' : fmtDate(end!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: end);
              if (d != null) setS(() => end = d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      )),
    );
    final n = int.tryParse(number.text.trim());
    if (ok == true && n != null && start != null && end != null) {
      final id = newId();
      await ref.read(adminDaoProvider).saveTerm(
          TermsCompanion(
              id: Value(id),
              academicYearId: Value(year.id),
              number: Value(n),
              startDate: Value(start!),
              endDate: Value(end!),
              createdAt: Value(nowIso()),
              updatedAt: Value(nowIso())),
          id,
          isNew: true);
      if (context.mounted) showSnack(context, S.saved);
    }
    number.dispose();
  }
}

class _PeriodsScreen extends ConsumerStatefulWidget {
  final Term term;
  const _PeriodsScreen({required this.term});

  @override
  ConsumerState<_PeriodsScreen> createState() => _PeriodsScreenState();
}

class _PeriodsScreenState extends ConsumerState<_PeriodsScreen> {
  List<CalendarPeriod> _periods = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(adminDaoProvider).periods(widget.term.id);
    if (mounted) setState(() => _periods = list);
  }

  Future<void> _add() async {
    final label = TextEditingController();
    CalendarKind kind = CalendarKind.vacation;
    String? start;
    String? end;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text(S.addPeriod),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Label')),
          const SizedBox(height: 12),
          DropdownButtonFormField<CalendarKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: CalendarKind.vacation, child: Text('Vacation')),
              DropdownMenuItem(value: CalendarKind.exam, child: Text('Exams')),
              DropdownMenuItem(value: CalendarKind.holiday, child: Text('Holiday')),
            ],
            onChanged: (v) => setS(() => kind = v ?? CalendarKind.vacation),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.from}: ${start == null ? '-' : fmtDate(start!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: start);
              if (d != null) setS(() => start = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.to}: ${end == null ? '-' : fmtDate(end!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await pickDate(ctx, initial: end);
              if (d != null) setS(() => end = d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.add)),
        ],
      )),
    );
    if (ok == true && label.text.trim().isNotEmpty && start != null && end != null) {
      final id = newId();
      await ref.read(adminDaoProvider).savePeriod(
          CalendarPeriodsCompanion(
              id: Value(id),
              termId: Value(widget.term.id),
              kind: Value(kind),
              label: Value(label.text.trim()),
              startDate: Value(start!),
              endDate: Value(end!),
              createdAt: Value(nowIso()),
              updatedAt: Value(nowIso())),
          id);
      await _load();
    }
    label.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Term ${widget.term.number} - ${S.vacationPeriods}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text(S.addPeriod),
      ),
      body: _periods.isEmpty
          ? const Center(child: Text(S.emptyList))
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final period in _periods)
                  ListTile(
                    leading: const Icon(Icons.event_busy),
                    title: Text(period.label),
                    subtitle: Text('${fmtDate(period.startDate)} to ${fmtDate(period.endDate)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDialog(context, S.delete, period.label);
                        if (ok) {
                          await ref.read(adminDaoProvider).deletePeriod(period.id);
                          await _load();
                        }
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ResetTermScreen extends ConsumerStatefulWidget {
  const _ResetTermScreen();

  @override
  ConsumerState<_ResetTermScreen> createState() => _ResetTermScreenState();
}

class _ResetTermScreenState extends ConsumerState<_ResetTermScreen> {
  final _number = TextEditingController();
  String? _start;
  String? _end;
  final Set<String> _chargeLevyIds = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final term = ref.read(currentTermProvider).valueOrNull;
    _number.text = '${(term?.number ?? 0) + 1}';
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final n = int.tryParse(_number.text.trim());
    if (n == null || n < 1 || n > 3 || _start == null || _end == null) {
      showSnack(context, 'Enter a term number (1-3) and both dates.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminDaoProvider).resetForNewTerm(number: n, startDate: _start!, endDate: _end!);
      var charged = 0;
      for (final id in _chargeLevyIds) {
        charged += await ref.read(financeDaoProvider).chargeLevy(id);
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'New term started. $charged due(s) charged.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levies = ref.watch(_leviesProvider).valueOrNull ?? [];
    final termly = levies.where((l) => l.isActive && l.frequency == LevyFrequency.termly).toList();
    return Scaffold(
      appBar: AppBar(title: const Text(S.resetForNewTerm)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(S.resetTermHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'New term number (1-3)')),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text('${S.from}: ${_start == null ? 'pick a date' : fmtDate(_start!)}'),
            onTap: () async {
              final d = await pickDate(context, initial: _start);
              if (d != null) setState(() => _start = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text('${S.to}: ${_end == null ? 'pick a date' : fmtDate(_end!)}'),
            onTap: () async {
              final d = await pickDate(context, initial: _end);
              if (d != null) setState(() => _end = d);
            },
          ),
          const SizedBox(height: 16),
          if (termly.isNotEmpty) ...[
            const SectionHeader('Charge these termly levies now'),
            for (final l in termly)
              CheckboxListTile(
                value: _chargeLevyIds.contains(l.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _chargeLevyIds.add(l.id);
                  } else {
                    _chargeLevyIds.remove(l.id);
                  }
                }),
                title: Text(l.name),
                subtitle: Text(formatGhs(l.amountPesewas)),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.restart_alt),
            label: const Text(S.resetForNewTerm),
          ),
        ],
      ),
    );
  }
}

class _PromotionScreen extends ConsumerStatefulWidget {
  const _PromotionScreen();

  @override
  ConsumerState<_PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends ConsumerState<_PromotionScreen> {
  final _yearName = TextEditingController();
  String? _start;
  String? _end;
  final List<(String?, String?)> _termDates = [(null, null), (null, null), (null, null)];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final year = ref.read(currentYearProvider).valueOrNull;
    if (year != null) {
      final match = RegExp(r'(\d{4})').firstMatch(year.name);
      if (match != null) {
        final y = int.parse(match.group(1)!);
        _yearName.text = '${y + 1}/${y + 2}';
        _start = dateOnly(DateTime(y + 1, 9, 1));
        _end = dateOnly(DateTime(y + 2, 7, 31));
      }
    }
  }

  @override
  void dispose() {
    _yearName.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final year = ref.read(currentYearProvider).valueOrNull;
    if (year == null) {
      showSnack(context, 'No current academic year.');
      return;
    }
    if (_yearName.text.trim().isEmpty || _start == null || _end == null ||
        _termDates.any((t) => t.$1 == null || t.$2 == null)) {
      showSnack(context, 'Fill in the year and all three term date ranges.');
      return;
    }
    final ok = await confirmDialog(context, S.promote, S.promoteConfirm);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final count = await ref.read(memberDaoProvider).promoteEndOfYear(
            currentYearId: year.id,
            newYearName: _yearName.text.trim(),
            newYearStart: _start!,
            newYearEnd: _end!,
            termDates: [
              for (var i = 0; i < 3; i++) (i + 1, _termDates[i].$1!, _termDates[i].$2!),
            ],
          );
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, '${S.promotionDone} $count member(s) processed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.promote)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(S.promoteConfirm, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
              controller: _yearName,
              decoration: const InputDecoration(labelText: 'New academic year name')),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text('Year ${S.from.toLowerCase()}: ${_start == null ? 'pick' : fmtDate(_start!)}'),
            onTap: () async {
              final d = await pickDate(context, initial: _start);
              if (d != null) setState(() => _start = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text('Year ${S.to.toLowerCase()}: ${_end == null ? 'pick' : fmtDate(_end!)}'),
            onTap: () async {
              final d = await pickDate(context, initial: _end);
              if (d != null) setState(() => _end = d);
            },
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            SectionHeader('Term ${i + 1} dates'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${S.from}: ${_termDates[i].$1 == null ? 'pick' : fmtDate(_termDates[i].$1!)}'),
              onTap: () async {
                final d = await pickDate(context, initial: _termDates[i].$1);
                if (d != null) setState(() => _termDates[i] = (d, _termDates[i].$2));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${S.to}: ${_termDates[i].$2 == null ? 'pick' : fmtDate(_termDates[i].$2!)}'),
              onTap: () async {
                final d = await pickDate(context, initial: _termDates[i].$2);
                if (d != null) setState(() => _termDates[i] = (_termDates[i].$1, d));
              },
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.school),
            label: const Text(S.promote),
          ),
        ],
      ),
    );
  }
}

class _UsersScreen extends ConsumerWidget {
  const _UsersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(_usersProvider);
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.usersAccounts)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const _UserEditScreen())),
        icon: const Icon(Icons.person_add),
        label: const Text(S.addUser),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final u in list)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(child: Text(initials(u.displayName))),
                  title: Text('${u.displayName}${u.id == me?.id ? ' (you)' : ''}'),
                  subtitle: Text(u.role.label),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      final dao = ref.read(adminDaoProvider);
                      if (v == 'pin') {
                        await _resetPinDialog(context, ref, u);
                      } else if (v == 'active') {
                        if (u.id == me?.id) {
                          showSnack(context, 'You cannot deactivate your own account.');
                          return;
                        }
                        await dao.setUserActive(u.id, !u.isActive);
                      } else if (v == 'biometric') {
                        final available = await Biometrics.available();
                        if (!available) {
                          if (context.mounted) {
                            showSnack(context, 'Biometrics not available on this device.');
                          }
                          return;
                        }
                        if (!u.biometricEnabled) {
                          final ok = await Biometrics.authenticate(S.useBiometrics);
                          if (!ok) return;
                        }
                        await dao.setBiometric(u.id, !u.biometricEnabled);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'pin', child: Text(S.resetPin)),
                      PopupMenuItem(
                          value: 'active',
                          child: Text(u.isActive ? 'Deactivate' : 'Activate')),
                      PopupMenuItem(
                          value: 'biometric',
                          child: Text(u.biometricEnabled
                              ? 'Disable biometric sign-in'
                              : 'Enable biometric sign-in')),
                    ],
                  ),
                ),
              ),
            if (list.any((u) => !u.isActive))
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Deactivated accounts cannot sign in.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPinDialog(BuildContext context, WidgetRef ref, User u) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.resetPin} - ${u.displayName}'),
        content: TextField(
          controller: pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(labelText: S.createPin),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok == true) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(pin.text)) {
        if (context.mounted) showSnack(context, S.pinTooShort);
      } else {
        await ref.read(adminDaoProvider).resetPin(u.id, pin.text);
        if (context.mounted) showSnack(context, S.saved);
      }
    }
    pin.dispose();
  }
}

class _UserEditScreen extends ConsumerStatefulWidget {
  const _UserEditScreen();

  @override
  ConsumerState<_UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends ConsumerState<_UserEditScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  ClubRole _role = ClubRole.secretary;
  String? _memberId;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || !RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) {
      showSnack(context, 'Enter a name and a 4-6 digit PIN.');
      return;
    }
    await ref.read(adminDaoProvider).createUser(
          displayName: _name.text.trim(),
          role: _role,
          pin: _pin.text,
          memberId: _role == ClubRole.member ? _memberId : null,
        );
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, S.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_activeMembersProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text(S.addUser)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: S.fullName)),
          const SizedBox(height: 16),
          DropdownButtonFormField<ClubRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: S.clubRole),
            items: [
              for (final r in ClubRole.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) => setState(() => _role = v ?? ClubRole.member),
          ),
          const SizedBox(height: 16),
          if (_role == ClubRole.member)
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: S.linkMember),
              items: [
                for (final m in members)
                  DropdownMenuItem(value: m.id, child: Text(m.fullName)),
              ],
              onChanged: (v) => setState(() => _memberId = v),
            ),
          if (_role == ClubRole.member) const SizedBox(height: 16),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(labelText: S.createPin),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _save, icon: const Icon(Icons.save), label: const Text(S.save)),
        ],
      ),
    );
  }
}

class _CategoriesScreen extends ConsumerStatefulWidget {
  const _CategoriesScreen();

  @override
  ConsumerState<_CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<_CategoriesScreen> {
  CategoryKind _kind = CategoryKind.expense;

  String _kindLabel(CategoryKind k) => switch (k) {
        CategoryKind.expense => 'Expense',
        CategoryKind.fine => 'Fine',
        CategoryKind.sessionType => 'Session type',
        CategoryKind.duesType => 'Dues type',
      };

  Future<void> _edit({Category? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? S.add : S.edit),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final id = existing?.id ?? newId();
      await ref.read(financeDaoProvider).saveCategory(
          CategoriesCompanion(
              id: Value(id),
              kind: Value(_kind),
              name: Value(name.text.trim()),
              createdAt: Value(existing?.createdAt ?? nowIso()),
              updatedAt: Value(nowIso())),
          id,
          isNew: existing == null);
      if (mounted) showSnack(context, S.saved);
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(_categoriesStreamProvider(_kind));
    return Scaffold(
      appBar: AppBar(title: const Text(S.categories)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text(S.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<CategoryKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final k in CategoryKind.values)
                  DropdownMenuItem(value: k, child: Text(_kindLabel(k))),
              ],
              onChanged: (v) => setState(() => _kind = v ?? CategoryKind.expense),
            ),
          ),
          Expanded(
            child: cats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text(S.emptyList))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        for (final c in list)
                          ListTile(
                            title: Text(c.name),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(existing: c)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await confirmDialog(context, S.delete, c.name);
                                  if (ok) {
                                    await ref.read(financeDaoProvider).saveCategory(
                                        CategoriesCompanion(
                                            id: Value(c.id),
                                            deletedAt: Value(nowIso()),
                                            updatedAt: Value(nowIso())),
                                        c.id,
                                        isNew: false);
                                  }
                                },
                              ),
                            ]),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

final _categoriesStreamProvider = StreamProvider.family<List<Category>, CategoryKind>(
    (ref, kind) => ref.watch(financeDaoProvider).watchCategories(kind));

class _BackupScreen extends ConsumerStatefulWidget {
  const _BackupScreen();

  @override
  ConsumerState<_BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<_BackupScreen> {
  final _password = TextEditingController();
  List<Backup> _backups = [];
  bool _autoBackup = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final list = await ref.read(adminDaoProvider).backups();
    final auto = await db.setting('auto_backup', fallback: '1');
    final pin = await db.setting('backup_pin', fallback: '');
    if (mounted) {
      setState(() {
        _backups = list;
        _autoBackup = auto == '1';
        if (pin.isNotEmpty) _password.text = pin;
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_password.text.length < 4) {
      showSnack(context, 'Use a backup password of at least 4 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await ref.read(adminDaoProvider).createBackup(_password.text);
      await ref.read(databaseProvider).setSetting('backup_pin', _password.text);
      await _load();
      if (mounted) showSnack(context, 'Backup saved: ${file.path}');
    } catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_password.text.isEmpty) {
      showSnack(context, 'Enter the password used when the backup was created.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wmb'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final ok = await confirmDialog(context, S.restoreBackup, S.restoreWarning);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final extracted = await ref.read(adminDaoProvider).extractBackup(File(path), _password.text);
      await ref.read(syncServiceProvider).stopHost();
      NotificationService.instance.dispose();
      final db = ref.read(databaseProvider);
      await db.close();
      final support = await getApplicationSupportDirectory();
      final dbFile = File(p.join(support.path, 'winroc.sqlite'));
      for (final suffix in ['-wal', '-shm']) {
        final side = File('${dbFile.path}$suffix');
        if (await side.exists()) await side.delete();
      }
      await dbFile.writeAsBytes(extracted.dbBytes, flush: true);
      await DbKeyStore.write(extracted.key);
      final newDb = await AppDatabase.open();
      NotificationService.instance.startPeriodicChecks(
          newDb, AttendanceDao(newDb), FinanceDao(newDb));
      runApp(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(newDb)],
        child: const WinrocApp(),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Restore failed (wrong password or corrupt file): $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.backup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(S.backupHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: S.backupPassword),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _autoBackup,
            onChanged: (v) async {
              await ref.read(databaseProvider).setSetting('auto_backup', v ? '1' : '0');
              setState(() => _autoBackup = v);
            },
            title: const Text(S.autoBackup),
            subtitle: const Text('Uses the password above; keeps the last 7 daily backups.'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.backup),
                label: const Text(S.createBackup),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text(S.restoreBackup),
              ),
            ),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          const SizedBox(height: 16),
          const SectionHeader('Previous backups'),
          if (_backups.isEmpty) const Text(S.emptyList),
          for (final b in _backups)
            ListTile(
              leading: Icon(b.kind == BackupKind.scheduled ? Icons.schedule : Icons.save_outlined),
              title: Text(p.basename(b.filePath)),
              subtitle: Text(
                  '${fmtDateTime(b.createdAt)} - ${(b.sizeBytes / 1024).toStringAsFixed(0)} KB${File(b.filePath).existsSync() ? '' : ' (file missing)'}'),
              trailing: IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => Share.shareXFiles([XFile(b.filePath)]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityScreen extends ConsumerWidget {
  const _ActivityScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(_activityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.activityLog)),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final l = list[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text('${l.action} - ${l.targetTable}'),
                    subtitle: Text(l.afterJson ?? l.recordId, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(fmtDateTime(l.createdAt),
                        style: Theme.of(context).textTheme.bodySmall),
                  );
                },
              ),
      ),
    );
  }
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.helpAbout)),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.data?.version ?? '...';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Image.asset('assets/branding/logo.jpg', height: 120),
              const SizedBox(height: 16),
              Text(S.appName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${S.clubName}\n${S.schoolName}', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(S.motto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              Text('${S.version}: $version', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const SectionHeader('How to use'),
              const Text(
                  '1. Add members in the Members tab (or import a CSV/Excel list).\n'
                  '2. Create a session in Attendance, then mark names, scan ID QR codes, or show the rotating session code.\n'
                  '3. Create levies in Dues, charge members, and record payments - receipts are automatic.\n'
                  '4. Print registers, ledgers and report cards from More > Reports.\n'
                  '5. Back up regularly in Settings > Backup & restore. Sync phone and PC over local Wi-Fi from More > Device sync.'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text(S.checkUpdates),
                    content: const Text(S.updateHint),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context), child: const Text(S.close)),
                    ],
                  ),
                ),
                icon: const Icon(Icons.system_update),
                label: const Text(S.checkUpdates),
              ),
              const SizedBox(height: 24),
              Text(S.guardianPrivacy,
                  style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}
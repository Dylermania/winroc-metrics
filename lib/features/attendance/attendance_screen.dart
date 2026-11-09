import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(currentTermProvider).value;
    final user = ref.watch(currentUserProvider);
    final canMark = user?.role.can(Capability.attendance) ?? false;
    final sessions = ref.watch(_sessionsProvider(term?.id));
    return Scaffold(
      floatingActionButton: canMark
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SessionEditScreen())),
              icon: const Icon(Icons.add),
              label: const Text(S.newSession))
          : null,
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (user?.role == ClubRole.member && user?.memberId != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text(S.scanSessionCode),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _SelfCheckinScanScreen(memberId: user!.memberId!))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text(S.excuses),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExcusesScreen())),
              ),
            ),
            for (final s in list)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: s.state == SessionState.ongoing
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    s.state == SessionState.closed ? Icons.event_available : Icons.event_outlined,
                    color: s.state == SessionState.ongoing
                        ? Theme.of(context).colorScheme.onPrimary
                        : null,
                  ),
                ),
                title: Text(s.title),
                subtitle: Text('${fmtDateShort(s.date)} · ${fmtTimeOfDay(s.startTime)} · ${s.type.label}'),
                trailing: s.state == SessionState.ongoing
                    ? const StatusChip('Live', Color(0xFF2E7D32))
                    : null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SessionScreen(sessionId: s.id))),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
          ],
        ),
      ),
    );
  }
}

final _sessionsProvider = StreamProvider.family<List<Session>, String?>(
    (ref, termId) => ref.watch(attendanceDaoProvider).watchSessions(termId: termId));

class SessionEditScreen extends ConsumerStatefulWidget {
  final Session? session;
  const SessionEditScreen({super.key, this.session});
  @override
  ConsumerState<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends ConsumerState<SessionEditScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  SessionType _type = SessionType.regular;
  CheckinMode _mode = CheckinMode.manual;
  String? _date;
  String? _start;
  String? _end;
  final _grace = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _date = s?.date ?? dateOnly(DateTime.now());
    _start = s?.startTime ?? '15:30';
    _end = s?.endTime;
    if (s != null) {
      _title.text = s.title;
      _location.text = s.location ?? '';
      _notes.text = s.notes ?? '';
      _type = s.type;
      _mode = s.checkinMode;
      _grace.text = s.graceMinutes?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _start == null) return;
    final term = ref.read(currentTermProvider).value;
    if (term == null) return;
    final blocked = await ref.read(adminDaoProvider).isDateBlocked(_date!);
    if (blocked && mounted) {
      final ok = await confirmDialog(context, 'Calendar', 'This date falls in a vacation/exam period. Create the session anyway?');
      if (!ok) return;
    }
    setState(() => _busy = true);
    final id = widget.session?.id ?? newId();
    final now = nowIso();
    await ref.read(attendanceDaoProvider).save(
      SessionsCompanion(
        id: Value(id),
        termId: Value(widget.session?.termId ?? term.id),
        type: Value(_type),
        title: Value(_title.text.trim()),
        location: Value(_location.text.trim().isEmpty ? null : _location.text.trim()),
        notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        date: Value(_date!),
        startTime: Value(_start!),
        endTime: Value(_end),
        graceMinutes: Value(int.tryParse(_grace.text)),
        state: Value(widget.session?.state ?? SessionState.scheduled),
        checkinMode: Value(_mode),
        selfCodeSecret: Value(widget.session?.selfCodeSecret ?? randomSecret()),
        createdBy: Value(widget.session?.createdBy ?? ref.read(databaseProvider).currentUserId),
        createdAt: Value(widget.session?.createdAt ?? now),
        updatedAt: Value(now),
      ),
      id,
      isNew: widget.session == null,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session == null ? S.newSession : S.edit)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: S.sessionTitle)),
        const SizedBox(height: 12),
        DropdownButtonFormField<SessionType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: S.sessionType),
          items: [for (final t in SessionType.values) DropdownMenuItem(value: t, child: Text(t.label))],
          onChanged: (v) => setState(() => _type = v ?? SessionType.regular),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${S.date}: ${fmtDateShort(_date)}'),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final d = await pickDate(context, initial: _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        Row(children: [
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${S.startTime}: ${_start == null ? '-' : fmtTimeOfDay(_start!)}'),
              onTap: () async {
                final t = await pickTime(context, initial: _start);
                if (t != null) setState(() => _start = t);
              },
            ),
          ),
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${S.endTime}: ${_end == null ? '-' : fmtTimeOfDay(_end!)}'),
              onTap: () async {
                final t = await pickTime(context, initial: _end);
                if (t != null) setState(() => _end = t);
              },
            ),
          ),
        ]),
        TextField(controller: _location, decoration: const InputDecoration(labelText: S.location)),
        const SizedBox(height: 12),
        TextField(
            controller: _grace,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '${S.gracePeriod} (${S.optional})')),
        const SizedBox(height: 12),
        DropdownButtonFormField<CheckinMode>(
          initialValue: _mode,
          decoration: const InputDecoration(labelText: S.checkinMode),
          items: const [
            DropdownMenuItem(value: CheckinMode.manual, child: Text(S.manualChecklist)),
            DropdownMenuItem(value: CheckinMode.qrScan, child: Text(S.scanMemberQr)),
            DropdownMenuItem(value: CheckinMode.selfCode, child: Text(S.selfCheckin)),
            DropdownMenuItem(value: CheckinMode.mixed, child: Text('Mixed (all methods)')),
          ],
          onChanged: (v) => setState(() => _mode = v ?? CheckinMode.manual),
        ),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: S.notes)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: const Text(S.save)),
      ]),
    );
  }
}

class SessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  bool _markingAll = false;

  Future<void> _setStatus(Session s, Member m, AttendanceRecord? existing, AttendanceStatus status) async {
    final dao = ref.read(attendanceDaoProvider);
    final db = ref.read(databaseProvider);
    var reason = '';
    if (existing != null && existing.status != status) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${m.fullName}: ${existing.status.label} → ${status.label}'),
          content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: S.editReasonHint)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text.trim();
    }
    final checkIn = status == AttendanceStatus.present || status == AttendanceStatus.late
        ? DateTime.now()
        : null;
    await dao.mark(s.id, m.id, status,
        checkInAt: checkIn, reason: reason.isEmpty ? 'Quick mark' : reason);
    if (status == AttendanceStatus.late) {
      final finePesewas = int.tryParse(await db.setting('late_fine_pesewas', fallback: '0')) ?? 0;
      if (finePesewas > 0 && mounted) {
        final apply = await confirmDialog(context, S.fines,
            'Apply automatic late fine of ${formatGhs(finePesewas)} to ${m.fullName}?');
        if (apply) {
          await ref.read(financeDaoProvider).addFine(
              memberId: m.id,
              category: 'Late Attendance',
              reason: 'Late for ${s.title} on ${s.date}',
              amountPesewas: finePesewas,
              sessionId: s.id,
              autoApplied: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(attendanceDaoProvider);
    final session = ref.watch(_sessionWatchProvider(widget.sessionId));
    final user = ref.watch(currentUserProvider);
    final canMark = user?.role.can(Capability.attendance) ?? false;
    final members = ref.watch(_activeMembersProvider);
    final records = ref.watch(_sessionRecordsProvider(widget.sessionId));
    return session.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (s) {
        if (s == null) return const Scaffold(body: Center(child: Text(S.noResults)));
        final recList = records.value ?? [];
        final byMember = {for (final r in recList) r.memberId: r};
        final closed = s.state == SessionState.closed;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.title),
            actions: [
              if (canMark)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SessionEditScreen(session: s))),
                ),
            ],
          ),
          body: Column(children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${fmtDateShort(s.date)} · ${fmtTimeOfDay(s.startTime)}'),
                StatusChip(s.type.label, Theme.of(context).colorScheme.primary),
                if (s.state == SessionState.ongoing) const StatusChip('Live', Color(0xFF2E7D32)),
                if (closed) const StatusChip(S.sessionClosed, Color(0xFF607D8B)),
                Text('${recList.where((r) => r.status.countsAsPresent).length}/${members.value?.length ?? 0} ${S.present.toLowerCase()}'),
              ]),
            ),
            if (canMark && !closed)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (s.state == SessionState.scheduled)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(S.startSession),
                      onPressed: () => dao.setState(s.id, SessionState.ongoing),
                    ),
                  if (s.state == SessionState.ongoing)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text(S.closeSession),
                      onPressed: () async {
                        final absent = (members.value ?? []).where((m) => !byMember.containsKey(m.id)).toList();
                        for (final m in absent) {
                          await dao.mark(s.id, m.id, AttendanceStatus.absent, reason: 'Session closed');
                        }
                        await dao.setState(s.id, SessionState.closed);
                      },
                    ),
                  if (!isDesktop(context) && (s.checkinMode == CheckinMode.qrScan || s.checkinMode == CheckinMode.mixed))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text(S.scanMemberQr),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _MemberQrScanScreen(session: s))),
                    ),
                  if (s.checkinMode == CheckinMode.selfCode || s.checkinMode == CheckinMode.mixed)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text(S.showSessionCode),
                      onPressed: () => showDialog(
                          context: context, builder: (_) => _SessionCodeDialog(session: s)),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text(S.verifyPending),
                    onPressed: () async {
                      final n = await dao.verifyPending(s.id);
                      if (context.mounted) showSnack(context, '$n verified');
                    },
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.done_all),
                    label: const Text(S.markAllPresent),
                    onPressed: _markingAll
                        ? null
                        : () async {
                            setState(() => _markingAll = true);
                            final grace = int.tryParse(await ref.read(databaseProvider).setting('grace_minutes', fallback: '15')) ?? 15;
                            await dao.markAllPresent(s.id, (members.value ?? []).map((m) => m.id).toList(), grace);
                            if (mounted) setState(() => _markingAll = false);
                          },
                  ),
                ]),
              ),
            Expanded(
              child: members.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (list) => ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final m = list[i];
                    final r = byMember[m.id];
                    return ListTile(
                      leading: MemberAvatar(m, radius: 18),
                      title: Text(m.fullName),
                      subtitle: r == null
                          ? null
                          : Text('${r.checkInAt != null ? fmtTime(r.checkInAt) : ''}${r.verified ? '' : ' · ${S.pendingVerification}'}'),
                      trailing: canMark && !closed
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              for (final st in AttendanceStatus.values)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: ChoiceChip(
                                    label: Text(st.label.substring(0, 1)),
                                    tooltip: st.label,
                                    selected: r?.status == st,
                                    onSelected: (_) => _setStatus(s, m, r, st),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              if (r != null)
                                IconButton(
                                  tooltip: S.editHistory,
                                  icon: const Icon(Icons.history, size: 20),
                                  onPressed: () async {
                                    final edits = await dao.editHistory(r.id);
                                    if (!context.mounted) return;
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text(S.editHistory),
                                        content: SizedBox(
                                          width: 380,
                                          child: edits.isEmpty
                                              ? const Text(S.emptyList)
                                              : ListView(shrinkWrap: true, children: [
                                                  for (final e in edits)
                                                    ListTile(
                                                      dense: true,
                                                      title: Text('${e.oldStatus.label} → ${e.newStatus.label}'),
                                                      subtitle: Text('${fmtDateTime(e.editedAt)} · ${e.reason}'),
                                                    ),
                                                ]),
                                        ),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close))],
                                      ),
                                    );
                                  },
                                ),
                            ])
                          : r == null
                              ? null
                              : StatusChip(r.status.label, r.status.color),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.note_add_outlined),
                label: const Text(S.meetingNotes),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _SessionNotesScreen(sessionId: s.id))),
              ),
            ),
          ]),
        );
      },
    );
  }
}

final _sessionWatchProvider =
    StreamProvider.family<Session?, String>((ref, id) => ref.watch(attendanceDaoProvider).watch(id));

final _activeMembersProvider =
    FutureProvider<List<Member>>((ref) => ref.watch(memberDaoProvider).activeMembers());

final _sessionRecordsProvider = StreamProvider.family<List<AttendanceRecord>, String>(
    (ref, id) => ref.watch(attendanceDaoProvider).watchRecords(id));

class _SessionCodeDialog extends StatefulWidget {
  final Session session;
  const _SessionCodeDialog({required this.session});
  @override
  State<_SessionCodeDialog> createState() => _SessionCodeDialogState();
}

class _SessionCodeDialogState extends State<_SessionCodeDialog> {
  Timer? _timer;
  int _bucket = currentBucket();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final b = currentBucket();
      if (b != _bucket) setState(() => _bucket = b);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = codeToken(widget.session.selfCodeSecret, _bucket);
    return AlertDialog(
      title: Text(S.selfCheckin),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(
            data: sessionCodeData(widget.session.id, token, _bucket),
            version: QrVersions.auto,
            size: 280,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          Text(token, style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 4)),
          const SizedBox(height: 8),
          const Text(S.codeHint, textAlign: TextAlign.center),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close))],
    );
  }
}

class _MemberQrScanScreen extends ConsumerStatefulWidget {
  final Session session;
  const _MemberQrScanScreen({required this.session});
  @override
  ConsumerState<_MemberQrScanScreen> createState() => _MemberQrScanScreenState();
}

class _MemberQrScanScreenState extends ConsumerState<_MemberQrScanScreen> {
  final _controller = MobileScannerController();
  bool _handling = false;
  String _last = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw == _last) return;
    _last = raw;
    _handling = true;
    final parsed = parseMemberQr(raw);
    if (parsed == null) {
      _handling = false;
      return;
    }
    final dao = ref.read(attendanceDaoProvider);
    final member = await ref.read(memberDaoProvider).get(parsed.memberId);
    if (!mounted) return;
    if (member == null || member.qrToken != parsed.token) {
      showSnack(context, 'Unknown member QR.');
      _handling = false;
      return;
    }
    final db = ref.read(databaseProvider);
    final grace = int.tryParse(await db.setting('grace_minutes', fallback: '15')) ?? 15;
    final status = dao.statusForCheckin(widget.session, DateTime.now(), grace);
    await dao.mark(widget.session.id, member.id, status,
        method: CheckinMethod.qrScan, checkInAt: DateTime.now());
    if (!mounted) return;
    showSnack(context, '${member.fullName}: ${status.label}');
    await Future.delayed(const Duration(seconds: 2));
    _last = '';
    _handling = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.scanMemberQr)),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}

class _SelfCheckinScanScreen extends ConsumerStatefulWidget {
  final String memberId;
  const _SelfCheckinScanScreen({required this.memberId});
  @override
  ConsumerState<_SelfCheckinScanScreen> createState() => _SelfCheckinScanScreenState();
}

class _SelfCheckinScanScreenState extends ConsumerState<_SelfCheckinScanScreen> {
  final _controller = MobileScannerController();
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = parseSessionCode(raw);
    if (parsed == null) return;
    _handling = true;
    final ok = await ref.read(attendanceDaoProvider).selfCheckin(
        parsed.sessionId, widget.memberId, parsed.token, parsed.bucket);
    if (!mounted) return;
    showSnack(context, ok ? S.checkedIn : S.invalidCode);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.scanSessionCode)),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}

class _SessionNotesScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const _SessionNotesScreen({required this.sessionId});
  @override
  ConsumerState<_SessionNotesScreen> createState() => _SessionNotesScreenState();
}

class _SessionNotesScreenState extends ConsumerState<_SessionNotesScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(_notesProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(title: Text(S.meetingNotes)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: S.title)),
        const SizedBox(height: 12),
        TextField(controller: _content, maxLines: 4, decoration: const InputDecoration(labelText: S.body)),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text(S.addNote),
          onPressed: () async {
            if (_title.text.trim().isEmpty) return;
            await ref.read(attendanceDaoProvider).addResource(
                widget.sessionId, ResourceKind.note, _title.text.trim(), _content.text.trim());
            _title.clear();
            _content.clear();
            ref.invalidate(_notesProvider(widget.sessionId));
          },
        ),
        const SizedBox(height: 16),
        notes.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [
            for (final n in list)
              Card(
                child: ListTile(
                  title: Text(n.title),
                  subtitle: Text(n.contentOrPath),
                  trailing: Text(fmtDateShort(n.createdAt)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

final _notesProvider = FutureProvider.family<List<SessionResource>, String>(
    (ref, id) => ref.watch(attendanceDaoProvider).resources(id));

class ExcusesScreen extends ConsumerWidget {
  const ExcusesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canReview = user?.role.can(Capability.attendance) ?? false;
    final excuses = ref.watch(_excusesProvider);
    final members = ref.watch(_activeMembersProvider);
    final sessions = ref.watch(_sessionsProvider(ref.watch(currentTermProvider).value?.id));
    return Scaffold(
      appBar: AppBar(title: Text(S.excuses)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text(S.submitExcuse),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _SubmitExcuseDialog(
              members: members.value ?? [], sessions: sessions.value ?? []),
        ),
      ),
      body: excuses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView(children: [
                for (final e in list)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(e.reason),
                      subtitle: Text('${fmtDateTime(e.submittedAt)} · ${e.status.label}${e.reviewNote != null ? ' · ${e.reviewNote}' : ''}'),
                      trailing: canReview && e.status == ExcuseStatus.pending
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: S.approve,
                                icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                onPressed: () => ref.read(attendanceDaoProvider).reviewExcuse(e.id, true, 'Approved'),
                              ),
                              IconButton(
                                tooltip: S.reject,
                                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                onPressed: () => ref.read(attendanceDaoProvider).reviewExcuse(e.id, false, 'Rejected'),
                              ),
                            ])
                          : StatusChip(
                              e.status.label,
                              e.status == ExcuseStatus.approved
                                  ? Colors.green
                                  : e.status == ExcuseStatus.rejected
                                      ? Colors.red
                                      : Colors.orange),
                    ),
                  ),
              ]),
      ),
    );
  }
}

final _excusesProvider =
    StreamProvider<List<Excuse>>((ref) => ref.watch(attendanceDaoProvider).watchExcuses());

class _SubmitExcuseDialog extends ConsumerStatefulWidget {
  final List<Member> members;
  final List<Session> sessions;
  const _SubmitExcuseDialog({required this.members, required this.sessions});
  @override
  ConsumerState<_SubmitExcuseDialog> createState() => _SubmitExcuseDialogState();
}

class _SubmitExcuseDialogState extends ConsumerState<_SubmitExcuseDialog> {
  Member? _member;
  Session? _session;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.submitExcuse),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<Member>(
            decoration: const InputDecoration(labelText: S.members),
            items: [for (final m in widget.members) DropdownMenuItem(value: m, child: Text(m.fullName))],
            onChanged: (v) => setState(() => _member = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Session>(
            decoration: const InputDecoration(labelText: S.sessions),
            items: [for (final s in widget.sessions) DropdownMenuItem(value: s, child: Text('${s.title} (${fmtDateShort(s.date)})'))],
            onChanged: (v) => setState(() => _session = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(labelText: S.reason)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            if (_member == null || _session == null || _reason.text.trim().isEmpty) return;
            await ref.read(attendanceDaoProvider).submitExcuse(_member!.id, _session!.id, _reason.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}
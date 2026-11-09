import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';
import '../reports/pdf_reports.dart';
import 'import_export.dart';

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});
  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _query = '';
  int? _form;
  String? _teamId;
  MemberStatus? _status;
  String _sort = 'name';
  bool _showAlumni = false;

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(memberDaoProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    final teams = ref.watch(_teamsProvider);
    final members = ref.watch(_membersStreamProvider((
      query: _query,
      form: _form,
      teamId: _teamId,
      status: _status,
      sort: _sort,
      alumni: _showAlumni,
    )));
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MemberEditScreen())),
              icon: const Icon(Icons.person_add_alt),
              label: const Text(S.addMember))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
                hintText: S.search, prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: DropdownButton<int?>(
                value: _form,
                hint: const Text(S.form),
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('${S.form}: all')),
                  for (var f = 1; f <= 3; f++)
                    DropdownMenuItem(value: f, child: Text('${S.form} $f')),
                ],
                onChanged: (v) => setState(() => _form = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: DropdownButton<String?>(
                value: _teamId,
                hint: const Text(S.teams),
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('${S.teams}: all')),
                  for (final t in teams.value ?? <Team>[])
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() => _teamId = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: DropdownButton<MemberStatus?>(
                value: _status,
                hint: const Text(S.status),
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('${S.status}: all')),
                  for (final s in MemberStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: DropdownButton<String>(
                value: _sort,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Sort: name')),
                  DropdownMenuItem(value: 'form', child: Text('Sort: form')),
                  DropdownMenuItem(value: 'joined', child: Text('Sort: joined')),
                ],
                onChanged: (v) => setState(() => _sort = v ?? 'name'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: FilterChip(
                label: const Text('Alumni'),
                selected: _showAlumni,
                onSelected: (v) => setState(() => _showAlumni = v),
              ),
            ),
          ]),
        ),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text(S.importCsv),
                onPressed: () async {
                  final n = await MemberImportExport.importFromFile(context, dao);
                  if (context.mounted) showSnack(context, '${S.importDone}: $n');
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_outlined),
                tooltip: S.exportCsv,
                onSelected: (v) async {
                  final include = v.endsWith('_g');
                  if (v.startsWith('csv')) {
                    await MemberImportExport.exportCsv(context, dao, include);
                  } else {
                    await MemberImportExport.exportExcel(context, dao, include);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'csv', child: Text(S.exportCsv)),
                  PopupMenuItem(value: 'xlsx', child: Text(S.exportExcel)),
                  PopupMenuItem(value: 'csv_g', child: Text('${S.exportCsv} + guardians')),
                ],
              ),
            ]),
          ),
        Expanded(
          child: members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? const Center(child: Text(S.emptyList))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final m = list[i];
                      return ListTile(
                        leading: MemberAvatar(m),
                        title: Text(m.fullName),
                        subtitle: Text('${S.form} ${m.form} · ${m.studentId}${m.house != null ? ' · ${m.house}' : ''}'),
                        trailing: StatusChip(m.status.label, m.status.color),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => MemberDetailScreen(memberId: m.id))),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

final _teamsProvider = StreamProvider<List<Team>>(
    (ref) => ref.watch(memberDaoProvider).watchTeams());

typedef _MemberFilter = ({
  String query,
  int? form,
  String? teamId,
  MemberStatus? status,
  String sort,
  bool alumni,
});

final _membersStreamProvider =
    StreamProvider.family<List<Member>, _MemberFilter>((ref, f) {
  return ref.watch(memberDaoProvider).watchMembers(
        query: f.query,
        form: f.form,
        teamId: f.teamId,
        status: f.status,
        sort: f.sort,
        includeArchived: f.alumni,
      );
});

class MemberEditScreen extends ConsumerStatefulWidget {
  final Member? member;
  const MemberEditScreen({super.key, this.member});
  @override
  ConsumerState<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends ConsumerState<MemberEditScreen> {
  final _name = TextEditingController();
  final _studentId = TextEditingController();
  final _house = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianContact = TextEditingController();
  final _notes = TextEditingController();
  int _form = 1;
  ClubRole _role = ClubRole.member;
  MemberStatus _status = MemberStatus.active;
  String? _joinDate;
  String? _birthday;
  String? _photoPath;
  Set<String> _teamIds = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m != null) {
      _name.text = m.fullName;
      _studentId.text = m.studentId;
      _house.text = m.house ?? '';
      _guardianName.text = m.guardianName ?? '';
      _guardianContact.text = m.guardianContact ?? '';
      _notes.text = m.notes ?? '';
      _form = m.form;
      _role = m.clubRole;
      _status = m.status;
      _joinDate = m.joinDate;
      _birthday = m.birthday;
      _photoPath = m.photoPath;
      ref.read(memberDaoProvider).teamsFor(m.id).then((teams) {
        if (mounted) setState(() => _teamIds = teams.map((t) => t.id).toSet());
      });
    } else {
      _joinDate = dateOnly(DateTime.now());
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _studentId, _house, _guardianName, _guardianContact, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty || _studentId.text.trim().isEmpty) {
      setState(() => _error = S.required);
      return;
    }
    final dao = ref.read(memberDaoProvider);
    if (await dao.studentIdExists(_studentId.text.trim(), exceptId: widget.member?.id)) {
      setState(() => _error = 'Student ID already exists.');
      return;
    }
    setState(() => _busy = true);
    final id = widget.member?.id ?? newId();
    final now = nowIso();
    await dao.save(
      MembersCompanion(
        id: Value(id),
        studentId: Value(_studentId.text.trim()),
        fullName: Value(_name.text.trim()),
        form: Value(_form),
        house: Value(_house.text.trim().isEmpty ? null : _house.text.trim()),
        guardianName: Value(_guardianName.text.trim().isEmpty ? null : _guardianName.text.trim()),
        guardianContact: Value(_guardianContact.text.trim().isEmpty ? null : _guardianContact.text.trim()),
        photoPath: Value(_photoPath),
        joinDate: Value(_joinDate ?? dateOnly(DateTime.now())),
        birthday: Value(_birthday),
        clubRole: Value(_role),
        status: Value(_status),
        qrToken: Value(widget.member?.qrToken ?? randomSecret()),
        notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        createdAt: Value(widget.member?.createdAt ?? now),
        updatedAt: Value(now),
      ),
      id,
      isNew: widget.member == null,
    );
    await dao.setTeams(id, _teamIds.toList());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(_teamsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.member == null ? S.addMember : S.editMember)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final path = await pickPhoto(context);
                if (path != null) setState(() => _photoPath = path);
              },
              child: CircleAvatar(
                radius: 44,
                backgroundImage: _photoPath != null ? FileImage(File(_photoPath!)) : null,
                child: _photoPath == null ? const Icon(Icons.add_a_photo_outlined, size: 32) : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: S.fullName)),
          const SizedBox(height: 12),
          TextField(controller: _studentId, decoration: const InputDecoration(labelText: S.studentId)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _form,
                decoration: const InputDecoration(labelText: S.form),
                items: [for (var f = 1; f <= 3; f++) DropdownMenuItem(value: f, child: Text('${S.form} $f'))],
                onChanged: (v) => setState(() => _form = v ?? 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _house, decoration: const InputDecoration(labelText: S.house))),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<ClubRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: S.clubRole),
            items: [for (final r in ClubRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (v) => setState(() => _role = v ?? ClubRole.member),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MemberStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: S.status),
            items: [for (final s in MemberStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _status = v ?? MemberStatus.active),
          ),
          const SizedBox(height: 12),
          TextField(controller: _guardianName, decoration: const InputDecoration(labelText: S.guardianName)),
          const SizedBox(height: 12),
          TextField(
              controller: _guardianContact,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: S.guardianContact)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.joinDate}: ${fmtDateShort(_joinDate)}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await pickDate(context, initial: _joinDate);
              if (d != null) setState(() => _joinDate = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.birthday}: ${_birthday == null ? '-' : fmtDateShort(_birthday)}'),
            trailing: const Icon(Icons.cake_outlined),
            onTap: () async {
              final d = await pickDate(context, initial: _birthday);
              if (d != null) setState(() => _birthday = d);
            },
          ),
          const SizedBox(height: 8),
          Text(S.teams, style: Theme.of(context).textTheme.titleSmall),
          for (final t in teams)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.name),
              value: _teamIds.contains(t.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _teamIds.add(t.id);
                } else {
                  _teamIds.remove(t.id);
                }
              }),
            ),
          TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: S.notes)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: const Text(S.save)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class MemberDetailScreen extends ConsumerWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.watch(memberDaoProvider);
    final member = ref.watch(_memberWatchProvider(memberId));
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    final canFinance = user?.role.can(Capability.finance) ?? false;
    return member.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (m) {
        if (m == null) return const Scaffold(body: Center(child: Text(S.noResults)));
        return Scaffold(
          appBar: AppBar(
            title: Text(m.fullName),
            actions: [
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MemberEditScreen(member: m))),
                ),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDialog(context, S.delete, '${S.delete} ${m.fullName}?');
                    if (!ok || !context.mounted) return;
                    await dao.softDelete(m.id);
                    if (context.mounted) {
                      Navigator.pop(context);
                      showUndo(context, S.deleted, () => dao.restore(m.id));
                    }
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                MemberAvatar(m, radius: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.fullName, style: Theme.of(context).textTheme.titleLarge),
                    Text('${S.form} ${m.form} · ${m.studentId} · ${m.clubRole.label}'),
                    const SizedBox(height: 6),
                    StatusChip(m.status.label, m.status.color),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              _MemberStats(memberId: m.id),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(S.idCard, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Center(
                      child: QrImageView(
                        data: memberQrData(m.id, m.qrToken),
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(child: Text(m.studentId, style: Theme.of(context).textTheme.titleSmall)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text(S.printIdCards),
                      onPressed: () => PdfReports.idCards(context, ref, [m]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              _MemberInfoCard(member: m),
              const SizedBox(height: 8),
              _MemberSkillsCard(memberId: m.id, canEdit: canEdit),
              const SizedBox(height: 8),
              _MemberBadgesCard(memberId: m.id),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text(S.reportCard),
                  onPressed: () => PdfReports.memberReportCard(context, ref, m),
                ),
                if (canFinance)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text(S.recordPayment),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _QuickPaymentScreen(member: m))),
                  ),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

final _memberWatchProvider =
    StreamProvider.family<Member?, String>((ref, id) => ref.watch(memberDaoProvider).watch(id));

class _MemberStats extends ConsumerWidget {
  final String memberId;
  const _MemberStats({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(currentTermProvider).value;
    final data = ref.watch(_memberStatsProvider((memberId, term?.id)));
    return data.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (s) => Row(children: [
        Expanded(child: StatCard(S.attendancePct, '${s.pct.toStringAsFixed(0)}%', Icons.fact_check_outlined, color: s.pct < s.threshold ? Colors.red : null)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(S.streak, '${s.streak}', Icons.local_fire_department_outlined)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(S.balance, formatGhs(s.owing), Icons.account_balance_wallet_outlined, color: s.owing > 0 ? Colors.red : null)),
      ]),
    );
  }
}

final _memberStatsProvider = FutureProvider.family<
    ({double pct, int streak, int owing, double threshold}), (String, String?)>((ref, args) async {
  final (id, termId) = args;
  final att = ref.watch(attendanceDaoProvider);
  final fin = ref.watch(financeDaoProvider);
  final db = ref.watch(databaseProvider);
  final pct = await att.attendancePct(id, termId: termId);
  final streak = await att.streak(id);
  final balance = await fin.balance(id);
  final threshold = double.tryParse(await db.setting('attendance_threshold', fallback: '75')) ?? 75;
  return (pct: pct, streak: streak, owing: balance.owing, threshold: threshold);
});

class _MemberInfoCard extends StatelessWidget {
  final Member member;
  const _MemberInfoCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final m = member;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.general, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _row(S.house, m.house ?? '-'),
          _row(S.memberSince, fmtDateShort(m.joinDate)),
          _row(S.birthday, m.birthday == null ? '-' : fmtDateShort(m.birthday)),
          _row(S.guardianName, m.guardianName ?? '-'),
          _row(S.guardianContact, m.guardianContact ?? '-'),
          if (m.notes != null) _row(S.notes, m.notes!),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );
}

class _MemberSkillsCard extends ConsumerWidget {
  final String memberId;
  final bool canEdit;
  const _MemberSkillsCard({required this.memberId, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.watch(memberDaoProvider);
    final data = ref.watch(_skillsProvider(memberId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.skills, style: Theme.of(context).textTheme.titleMedium),
          data.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (skills) => Column(children: [
              for (final s in skills.$1)
                Row(children: [
                  SizedBox(width: 110, child: Text(s.name)),
                  Expanded(
                    child: Slider(
                      value: (skills.$2[s.id] ?? 0).toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      label: '${skills.$2[s.id] ?? 0}',
                      onChanged: canEdit
                          ? (v) => dao.setSkill(memberId, s.id, v.round())
                          : null,
                    ),
                  ),
                  Text('${skills.$2[s.id] ?? 0}/5'),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

final _skillsProvider = FutureProvider.family<(List<Skill>, Map<String, int>), String>((ref, id) async {
  final dao = ref.watch(memberDaoProvider);
  return (await dao.allSkills(), await dao.skillsFor(id));
});

class _MemberBadgesCard extends ConsumerWidget {
  final String memberId;
  const _MemberBadgesCard({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_badgesProvider(memberId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.badges, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          data.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (badges) => badges.$2.isEmpty
                ? const Text(S.emptyList)
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final mb in badges.$2)
                      Chip(
                        avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                        label: Text(badges.$1.where((b) => b.id == mb.badgeId).firstOrNull?.name ?? 'Badge'),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

final _badgesProvider = FutureProvider.family<(List<Badge>, List<MemberBadge>), String>((ref, id) async {
  final dao = ref.watch(clubDaoProvider);
  return (await dao.allBadges(), await dao.badgesFor(id));
});

class _QuickPaymentScreen extends ConsumerStatefulWidget {
  final Member member;
  const _QuickPaymentScreen({required this.member});
  @override
  ConsumerState<_QuickPaymentScreen> createState() => _QuickPaymentScreenState();
}

class _QuickPaymentScreenState extends ConsumerState<_QuickPaymentScreen> {
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = ref.watch(currentTermProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text('${S.recordPayment} — ${widget.member.fullName}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MoneyField(_amount),
        const SizedBox(height: 12),
        DropdownButtonFormField<PaymentMethod>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: S.paymentMethod),
          items: [for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
          onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
        ),
        const SizedBox(height: 12),
        TextField(controller: _ref, decoration: const InputDecoration(labelText: '${S.transactionRef} (${S.optional})')),
        const SizedBox(height: 8),
        const Text(S.allocateHint),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || term == null
              ? null
              : () async {
                  final amount = parseGhs(_amount.text);
                  if (amount <= 0) return;
                  setState(() => _busy = true);
                  final payment = await ref.read(financeDaoProvider).recordPayment(
                        memberId: widget.member.id,
                        amountPesewas: amount,
                        method: _method,
                        transactionRef: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
                        termId: term.id,
                      );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await PdfReports.receipt(context, ref, payment, widget.member);
                },
          child: const Text(S.recordPayment),
        ),
      ]),
    );
  }
}
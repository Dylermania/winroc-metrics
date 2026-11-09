import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/daos/finance_dao.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';
import '../reports/pdf_reports.dart';

class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canFinance = user?.role.can(Capability.finance) ?? false;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(S.dues),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: S.levies),
            Tab(text: S.balance),
            Tab(text: S.defaulters),
            Tab(text: S.fines),
            Tab(text: S.expenses),
          ]),
        ),
        body: TabBarView(children: [
          _LeviesTab(canEdit: canFinance),
          _BalancesTab(canEdit: canFinance),
          _DefaultersTab(canEdit: canFinance),
          _FinesTab(canEdit: canFinance),
          _ExpensesTab(canEdit: canFinance),
        ]),
      ),
    );
  }
}

class _LeviesTab extends ConsumerWidget {
  final bool canEdit;
  const _LeviesTab({required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levies = ref.watch(_leviesProvider);
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _LevyEditScreen())),
              icon: const Icon(Icons.add),
              label: const Text(S.newLevy))
          : null,
      body: levies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView(children: [
                for (final l in list)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(l.name),
                      subtitle: Text('${formatGhs(l.amountPesewas)} · ${l.frequency.label}${l.appliesTo == 'team' ? ' · team only' : ''}'),
                      trailing: canEdit
                          ? FilledButton.tonal(
                              child: const Text(S.chargeMembers),
                              onPressed: () async {
                                final ok = await confirmDialog(context, S.chargeMembers,
                                    'Charge ${formatGhs(l.amountPesewas)} to all applicable members?');
                                if (!ok || !context.mounted) return;
                                final n = await ref.read(financeDaoProvider).chargeLevy(l.id);
                                if (context.mounted) showSnack(context, '${S.charged} ($n)');
                              },
                            )
                          : null,
                    ),
                  ),
              ]),
      ),
    );
  }
}

final _leviesProvider =
    StreamProvider<List<Levy>>((ref) => ref.watch(financeDaoProvider).watchLevies());

class _LevyEditScreen extends ConsumerStatefulWidget {
  const _LevyEditScreen();
  @override
  ConsumerState<_LevyEditScreen> createState() => _LevyEditScreenState();
}

class _LevyEditScreenState extends ConsumerState<_LevyEditScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  LevyFrequency _freq = LevyFrequency.termly;
  bool _teamOnly = false;
  String? _teamId;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(_teamsStream).value ?? [];
    final term = ref.watch(currentTermProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(S.newLevy)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: S.levyName)),
        const SizedBox(height: 12),
        MoneyField(_amount),
        const SizedBox(height: 12),
        DropdownButtonFormField<LevyFrequency>(
          initialValue: _freq,
          decoration: const InputDecoration(labelText: S.frequency),
          items: [for (final f in LevyFrequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
          onChanged: (v) => setState(() => _freq = v ?? LevyFrequency.termly),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(S.teamOnly),
          value: _teamOnly,
          onChanged: (v) => setState(() => _teamOnly = v),
        ),
        if (_teamOnly)
          DropdownButtonFormField<String>(
            initialValue: _teamId,
            decoration: const InputDecoration(labelText: S.teams),
            items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setState(() => _teamId = v),
          ),
        const SizedBox(height: 12),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: '${S.description} (${S.optional})')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final amount = parseGhs(_amount.text);
            if (_name.text.trim().isEmpty || amount <= 0) return;
            final id = newId();
            await ref.read(financeDaoProvider).saveLevy(
              LeviesCompanion.insert(
                id: id,
                name: _name.text.trim(),
                description: Value(_desc.text.trim().isEmpty ? null : _desc.text.trim()),
                amountPesewas: amount,
                frequency: _freq,
                termId: Value(_freq == LevyFrequency.oneOff ? null : term?.id),
                appliesTo: Value(_teamOnly ? 'team' : 'all'),
                teamId: Value(_teamOnly ? _teamId : null),
                createdBy: ref.read(databaseProvider).currentUserId,
                createdAt: nowIso(),
                updatedAt: nowIso(),
              ),
              id,
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ]),
    );
  }
}

final _teamsStream =
    StreamProvider<List<Team>>((ref) => ref.watch(memberDaoProvider).watchTeams());

class _BalancesTab extends ConsumerWidget {
  final bool canEdit;
  const _BalancesTab({required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(_activeMembersStream);
    return members.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final m = list[i];
          final bal = ref.watch(_balanceProvider(m.id)).value;
          return ListTile(
            leading: MemberAvatar(m, radius: 18),
            title: Text(m.fullName),
            subtitle: bal == null
                ? null
                : Text('${S.paid}: ${formatGhs(bal.paid)} · ${S.credit}: ${formatGhs(bal.credit)}'),
            trailing: bal == null
                ? null
                : StatusChip(
                    bal.owing > 0 ? '${S.owing} ${formatGhs(bal.owing)}' : (bal.credit > 0 ? S.overpaid : S.paid),
                    bal.owing > 0 ? Colors.red : Colors.green),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MemberDuesScreen(member: m, canEdit: canEdit))),
          );
        },
      ),
    );
  }
}

final _activeMembersStream =
    FutureProvider<List<Member>>((ref) => ref.watch(memberDaoProvider).activeMembers());

final _balanceProvider = FutureProvider.family<MemberBalance, String>(
    (ref, id) => ref.watch(financeDaoProvider).balance(id));

class MemberDuesScreen extends ConsumerWidget {
  final Member member;
  final bool canEdit;
  const MemberDuesScreen({super.key, required this.member, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(_duesProvider(member.id));
    final payments = ref.watch(_paymentsProvider(member.id));
    final bal = ref.watch(_balanceProvider(member.id)).value;
    return Scaffold(
      appBar: AppBar(title: Text('${S.dues} — ${member.fullName}')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_card),
              label: const Text(S.recordPayment),
              onPressed: () => showDialog(
                  context: context, builder: (_) => PaymentDialog(member: member)))
          : null,
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (bal != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: StatCard(S.owing, formatGhs(bal.owing), Icons.money_off_outlined, color: bal.owing > 0 ? Colors.red : null)),
              const SizedBox(width: 8),
              Expanded(child: StatCard(S.paid, formatGhs(bal.paid), Icons.check_circle_outline)),
              const SizedBox(width: 8),
              Expanded(child: StatCard(S.credit, formatGhs(bal.credit), Icons.savings_outlined)),
            ]),
          ),
        SectionHeader(S.levies),
        dues.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [
            for (final d in list)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(d.label),
                  subtitle: Text('${formatGhs(d.due.amountPesewas)}${d.due.waiverPesewas > 0 ? ' · ${S.waiver}: ${formatGhs(d.due.waiverPesewas)}' : ''} · ${S.paid}: ${formatGhs(d.allocated)}'),
                  trailing: canEdit && d.remaining > 0
                      ? IconButton(
                          tooltip: S.waiver,
                          icon: const Icon(Icons.percent),
                          onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _WaiverDialog(due: d)),
                        )
                      : StatusChip(d.remaining > 0 ? S.owing : S.paid, d.remaining > 0 ? Colors.red : Colors.green),
                ),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text(S.emptyList)),
          ]),
        ),
        SectionHeader(S.receipts),
        payments.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [
            for (final p in list)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${p.receiptNo} · ${formatGhs(p.amountPesewas)}'),
                subtitle: Text('${fmtDateTime(p.paidAt)} · ${p.method.label}'),
                trailing: IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => PdfReports.receipt(context, ref, p, member),
                ),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text(S.emptyList)),
          ]),
        ),
      ]),
    );
  }
}

final _duesProvider = FutureProvider.family<List<DueWithBalance>, String>(
    (ref, id) => ref.watch(financeDaoProvider).duesWithBalances(id));

final _paymentsProvider = StreamProvider.family<List<Payment>, String>(
    (ref, id) => ref.watch(financeDaoProvider).watchPayments(memberId: id));

class PaymentDialog extends ConsumerStatefulWidget {
  final Member member;
  const PaymentDialog({super.key, required this.member});
  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
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
    return AlertDialog(
      title: Text('${S.recordPayment} — ${widget.member.fullName}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          const Text(S.allocateHint, style: TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
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
                  ref.invalidate(_balanceProvider(widget.member.id));
                  ref.invalidate(_duesProvider(widget.member.id));
                  await PdfReports.receipt(context, ref, payment, widget.member);
                },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class _WaiverDialog extends ConsumerStatefulWidget {
  final DueWithBalance due;
  const _WaiverDialog({required this.due});
  @override
  ConsumerState<_WaiverDialog> createState() => _WaiverDialogState();
}

class _WaiverDialogState extends ConsumerState<_WaiverDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${S.waiver} — ${widget.due.label}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MoneyField(_amount, label: '${S.waiver} (${S.amount})'),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: S.waiverReason)),
          const SizedBox(height: 8),
          Text('${S.approver}: ${ref.watch(currentUserProvider)?.displayName ?? ''}', style: const TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final amount = parseGhs(_amount.text);
            if (amount <= 0 || _reason.text.trim().isEmpty) return;
            await ref.read(financeDaoProvider).waive(widget.due.due.id, amount, _reason.text.trim());
            if (context.mounted) {
              Navigator.pop(context);
              ref.invalidate(_duesProvider(widget.due.due.memberId));
              ref.invalidate(_balanceProvider(widget.due.due.memberId));
            }
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class _DefaultersTab extends ConsumerWidget {
  final bool canEdit;
  const _DefaultersTab({required this.canEdit});

  Future<void> _reminder(BuildContext context, WidgetRef ref, Defaulter d) async {
    final db = ref.read(databaseProvider);
    final templates = await ref.read(clubDaoProvider).watchTemplates().first;
    final template = templates.where((t) => t.kind == TemplateKind.duesReminder).firstOrNull;
    final school = await db.setting('school_name', fallback: Defaults.schoolName);
    final club = await db.setting('club_name', fallback: Defaults.clubName);
    final body = fillTemplate(template?.body ?? '{name} has an outstanding balance of {balance}.', {
      'name': d.member.fullName,
      'guardian': d.member.guardianName ?? 'Parent/Guardian',
      'balance': formatGhs(d.owing),
      'school': school,
      'club': club,
    });
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) {
      showSnack(context, S.copyMessage);
      await Share.share(body, subject: 'Dues reminder — ${d.member.fullName}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaulters = ref.watch(_defaultersProvider);
    return Scaffold(
      body: defaulters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text(S.exportPdf),
              onPressed: () => PdfReports.defaultersList(context, ref),
            ),
          ),
          for (final d in list)
            ListTile(
              leading: MemberAvatar(d.member, radius: 18),
              title: Text(d.member.fullName),
              subtitle: Text('${S.form} ${d.member.form} · ${d.member.guardianContact ?? '-'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatGhs(d.owing), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                if (canEdit)
                  IconButton(
                    tooltip: S.sendReminder,
                    icon: const Icon(Icons.message_outlined),
                    onPressed: () => _reminder(context, ref, d),
                  ),
              ]),
            ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
        ]),
      ),
    );
  }
}

final _defaultersProvider =
    FutureProvider<List<Defaulter>>((ref) => ref.watch(financeDaoProvider).defaulters());

class _FinesTab extends ConsumerWidget {
  final bool canEdit;
  const _FinesTab({required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fines = ref.watch(_finesProvider);
    final members = ref.watch(_activeMembersStream).value ?? [];
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text(S.newFine),
              onPressed: () => showDialog(
                  context: context, builder: (_) => _FineDialog(members: members)))
          : null,
      body: fines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(children: [
          for (final f in list)
            ListTile(
              title: Text('${f.category} · ${formatGhs(f.amountPesewas)}'),
              subtitle: Text('${f.reason}${f.autoApplied ? ' (auto)' : ''} · ${fmtDateShort(f.createdAt)}'),
              trailing: canEdit && f.status == FineStatus.open
                  ? PopupMenuButton<String>(
                      onSelected: (v) => ref.read(financeDaoProvider).setFineStatus(
                          f.id, v == 'settle' ? FineStatus.settled : FineStatus.waived),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'settle', child: Text('Mark settled')),
                        PopupMenuItem(value: 'waive', child: Text(S.waiver)),
                      ],
                    )
                  : StatusChip(f.status.label, f.status == FineStatus.open ? Colors.red : Colors.green),
            ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
        ]),
      ),
    );
  }
}

final _finesProvider =
    StreamProvider<List<Fine>>((ref) => ref.watch(financeDaoProvider).watchFines());

class _FineDialog extends ConsumerStatefulWidget {
  final List<Member> members;
  const _FineDialog({required this.members});
  @override
  ConsumerState<_FineDialog> createState() => _FineDialogState();
}

class _FineDialogState extends ConsumerState<_FineDialog> {
  Member? _member;
  String _category = 'Late Attendance';
  final _reason = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(_fineCategoriesProvider).value ?? [];
    return AlertDialog(
      title: Text(S.newFine),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<Member>(
            decoration: const InputDecoration(labelText: S.members),
            items: [for (final m in widget.members) DropdownMenuItem(value: m, child: Text(m.fullName))],
            onChanged: (v) => setState(() => _member = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: S.fineCategory),
            items: [
              for (final c in categories) DropdownMenuItem(value: c.name, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          MoneyField(_amount),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: S.reason)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final amount = parseGhs(_amount.text);
            if (_member == null || amount <= 0 || _reason.text.trim().isEmpty) return;
            await ref.read(financeDaoProvider).addFine(
                memberId: _member!.id,
                category: _category,
                reason: _reason.text.trim(),
                amountPesewas: amount);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

final _fineCategoriesProvider = FutureProvider<List<Category>>(
    (ref) => ref.watch(financeDaoProvider).categories(CategoryKind.fine));

class _ExpensesTab extends ConsumerWidget {
  final bool canEdit;
  const _ExpensesTab({required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(_expensesProvider);
    final categories = ref.watch(_expenseCategoriesProvider).value ?? [];
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text(S.newExpense),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _ExpenseDialog(categories: categories)))
          : null,
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(children: [
          for (final e in list)
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(e.description),
              subtitle: Text('${fmtDateShort(e.spentAt)} · ${categories.where((c) => c.id == e.categoryId).firstOrNull?.name ?? ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatGhs(e.amountPesewas)),
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await ref.read(financeDaoProvider).softDeleteExpense(e.id);
                    },
                  ),
              ]),
            ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
        ]),
      ),
    );
  }
}

final _expensesProvider =
    StreamProvider<List<Expense>>((ref) => ref.watch(financeDaoProvider).watchExpenses());

final _expenseCategoriesProvider = FutureProvider<List<Category>>(
    (ref) => ref.watch(financeDaoProvider).categories(CategoryKind.expense));

class _ExpenseDialog extends ConsumerStatefulWidget {
  final List<Category> categories;
  const _ExpenseDialog({required this.categories});
  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  Category? _category;
  String? _photo;
  String? _date;

  @override
  void initState() {
    super.initState();
    _date = dateOnly(DateTime.now());
    _category = widget.categories.firstOrNull;
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.newExpense),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _desc, decoration: const InputDecoration(labelText: S.description)),
            const SizedBox(height: 12),
            MoneyField(_amount),
            const SizedBox(height: 12),
            DropdownButtonFormField<Category>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: S.expenseCategory),
              items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c.name))],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${S.date}: ${fmtDateShort(_date)}'),
              onTap: () async {
                final d = await pickDate(context, initial: _date);
                if (d != null) setState(() => _date = d);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: Text(_photo == null ? S.receiptPhoto : 'Photo attached'),
              onPressed: () async {
                final path = await pickPhoto(context);
                if (path != null) setState(() => _photo = path);
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final amount = parseGhs(_amount.text);
            if (_desc.text.trim().isEmpty || amount <= 0 || _category == null) return;
            final id = newId();
            await ref.read(financeDaoProvider).saveExpense(
              ExpensesCompanion.insert(
                id: id,
                categoryId: _category!.id,
                description: _desc.text.trim(),
                amountPesewas: amount,
                spentAt: '${_date}T12:00:00',
                receiptPhotoPath: Value(_photo),
                recordedBy: ref.read(databaseProvider).currentUserId,
                createdAt: nowIso(),
                updatedAt: nowIso(),
              ),
              id,
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}
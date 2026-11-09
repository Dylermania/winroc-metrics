import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../database.dart';

class MemberBalance {
  final int charged;
  final int waived;
  final int paid;
  final int totalPayments;
  MemberBalance(this.charged, this.waived, this.paid, this.totalPayments);
  int get netCharged => charged - waived;
  int get owing => (netCharged - paid).clamp(0, 1 << 62);
  int get credit => (totalPayments - netCharged).clamp(0, 1 << 62);
}

class DueWithBalance {
  final MemberDue due;
  final String label;
  final int allocated;
  DueWithBalance(this.due, this.label, this.allocated);
  int get remaining => (due.amountPesewas - due.waiverPesewas - allocated).clamp(0, 1 << 62);
}

class Defaulter {
  final Member member;
  final int owing;
  Defaulter(this.member, this.owing);
}

class FinanceDao {
  final AppDatabase db;
  FinanceDao(this.db);

  Stream<List<Levy>> watchLevies() =>
      (db.select(db.levies)..where((l) => l.deletedAt.isNull())..orderBy([(l) => OrderingTerm(expression: l.createdAt, mode: OrderingMode.desc)])).watch();

  Future<Levy?> levy(String id) =>
      (db.select(db.levies)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<void> saveLevy(LeviesCompanion c, String id, {required bool isNew}) async {
    await db.into(db.levies).insertOnConflictUpdate(c);
    await db.logChange('levies', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'levies', id);
  }

  Future<int> chargeLevy(String levyId) async {
    final levy = await this.levy(levyId);
    if (levy == null) return 0;
    var members = await (db.select(db.members)
          ..where((m) =>
              m.deletedAt.isNull() &
              m.status.isInValues([MemberStatus.active, MemberStatus.probation])))
        .get();
    if (levy.appliesTo == 'team' && levy.teamId != null) {
      final ids = await (db.select(db.memberTeams)
            ..where((t) => t.teamId.equals(levy.teamId!) & t.deletedAt.isNull()))
          .get();
      final idSet = ids.map((e) => e.memberId).toSet();
      members = members.where((m) => idSet.contains(m.id)).toList();
    }
    var count = 0;
    for (final m in members) {
      final existing = await (db.select(db.memberDues)
            ..where((d) => d.levyId.equals(levyId) & d.memberId.equals(m.id) & d.deletedAt.isNull()))
          .getSingleOrNull();
      if (existing != null) {
        // Termly levies may be charged again once a new term starts.
        if (levy.frequency != LevyFrequency.termly) continue;
        final term = await (db.select(db.terms)..where((t) => t.isCurrent.equals(true))).getSingleOrNull();
        if (term == null || existing.createdAt.substring(0, 10).compareTo(term.startDate) >= 0) {
          continue;
        }
      }
      final id = newId();
      await db.into(db.memberDues).insert(MemberDuesCompanion.insert(
          id: id,
          levyId: Value(levyId),
          memberId: m.id,
          amountPesewas: levy.amountPesewas,
          createdAt: nowIso(),
          updatedAt: nowIso()));
      await db.logChange('member_dues', id, SyncOp.insert);
      count++;
    }
    await db.audit('charge_levy', 'levies', levyId, after: '$count members');
    return count;
  }

  Future<List<MemberDue>> duesFor(String memberId) =>
      (db.select(db.memberDues)
            ..where((d) => d.memberId.equals(memberId) & d.deletedAt.isNull())
            ..orderBy([(d) => OrderingTerm(expression: d.createdAt)]))
          .get();

  Future<List<DueWithBalance>> duesWithBalances(String memberId) async {
    final dues = await duesFor(memberId);
    final out = <DueWithBalance>[];
    for (final d in dues) {
      final allocs = await (db.select(db.paymentAllocations)
            ..where((a) => a.memberDueId.equals(d.id) & a.deletedAt.isNull()))
          .get();
      final allocated = allocs.fold<int>(0, (s, a) => s + a.amountPesewas);
      String label = 'Charge';
      if (d.levyId != null) {
        label = (await levy(d.levyId!))?.name ?? 'Levy';
      } else if (d.source == 'fine') {
        label = 'Fine';
      }
      out.add(DueWithBalance(d, label, allocated));
    }
    return out;
  }

  Future<MemberBalance> balance(String memberId) async {
    final dues = await duesFor(memberId);
    final charged = dues.fold<int>(0, (s, d) => s + d.amountPesewas);
    final waived = dues.fold<int>(0, (s, d) => s + d.waiverPesewas);
    final dueIds = dues.map((d) => d.id).toSet();
    final allocs = await (db.select(db.paymentAllocations)
          ..where((a) => a.deletedAt.isNull()))
        .get();
    final paid = allocs
        .where((a) => dueIds.contains(a.memberDueId))
        .fold<int>(0, (s, a) => s + a.amountPesewas);
    final payments = await (db.select(db.payments)
          ..where((p) => p.memberId.equals(memberId) & p.deletedAt.isNull()))
        .get();
    final total = payments.fold<int>(0, (s, p) => s + p.amountPesewas);
    return MemberBalance(charged, waived, paid, total);
  }

  Future<String> _nextReceiptNo() async {
    final year = DateTime.now().year;
    final count = await db.payments.count().getSingle();
    var n = count + 1;
    while (true) {
      final no = 'WR-$year-${n.toString().padLeft(4, '0')}';
      final exists = await (db.select(db.payments)..where((p) => p.receiptNo.equals(no))).getSingleOrNull();
      if (exists == null) return no;
      n++;
    }
  }

  Future<Payment> recordPayment({
    required String memberId,
    required int amountPesewas,
    required PaymentMethod method,
    String? transactionRef,
    required String termId,
    String? notes,
  }) async {
    final id = newId();
    final receiptNo = await _nextReceiptNo();
    final payment = Payment(
      id: id,
      memberId: memberId,
      receiptNo: receiptNo,
      amountPesewas: amountPesewas,
      method: method,
      transactionRef: transactionRef,
      termId: termId,
      receivedBy: db.currentUserId,
      paidAt: nowIso(),
      notes: notes,
      createdAt: nowIso(),
      updatedAt: nowIso(),
      deletedAt: null,
    );
    await db.into(db.payments).insert(PaymentsCompanion.insert(
        id: id,
        memberId: memberId,
        receiptNo: receiptNo,
        amountPesewas: amountPesewas,
        method: method,
        transactionRef: Value(transactionRef),
        termId: termId,
        receivedBy: db.currentUserId,
        paidAt: payment.paidAt,
        notes: Value(notes),
        createdAt: payment.createdAt,
        updatedAt: payment.updatedAt));
    await db.logChange('payments', id, SyncOp.insert);

    var left = amountPesewas;
    final dues = await duesWithBalances(memberId);
    for (final d in dues) {
      if (left <= 0) break;
      if (d.remaining <= 0) continue;
      final take = left < d.remaining ? left : d.remaining;
      final aid = newId();
      await db.into(db.paymentAllocations).insert(PaymentAllocationsCompanion.insert(
          id: aid,
          paymentId: id,
          memberDueId: d.due.id,
          amountPesewas: take,
          createdAt: nowIso(),
          updatedAt: nowIso()));
      await db.logChange('payment_allocations', aid, SyncOp.insert);
      left -= take;
    }
    await db.audit('record_payment', 'payments', id,
        after: jsonEncode({'receipt': receiptNo, 'amount': amountPesewas, 'method': method.name}));
    return payment;
  }

  Stream<List<Payment>> watchPayments({String? termId, String? memberId}) {
    var q = db.select(db.payments)..where((p) => p.deletedAt.isNull());
    if (termId != null) q = q..where((p) => p.termId.equals(termId));
    if (memberId != null) q = q..where((p) => p.memberId.equals(memberId));
    q = q..orderBy([(p) => OrderingTerm(expression: p.paidAt, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<Payment?> paymentByReceipt(String receiptNo) =>
      (db.select(db.payments)..where((p) => p.receiptNo.equals(receiptNo))).getSingleOrNull();

  Future<void> waive(String dueId, int amount, String reason) async {
    final due = await (db.select(db.memberDues)..where((d) => d.id.equals(dueId))).getSingle();
    final newWaiver = (due.waiverPesewas + amount).clamp(0, due.amountPesewas);
    await (db.update(db.memberDues)..where((d) => d.id.equals(dueId))).write(MemberDuesCompanion(
        waiverPesewas: Value(newWaiver),
        waiverReason: Value(reason),
        waivedBy: Value(db.currentUserId),
        updatedAt: Value(nowIso())));
    await db.logChange('member_dues', dueId, SyncOp.update);
    await db.audit('waive', 'member_dues', dueId, after: '$newWaiver pesewas: $reason');
  }

  Future<void> addFine({
    required String memberId,
    required String category,
    required String reason,
    required int amountPesewas,
    String? sessionId,
    bool autoApplied = false,
  }) async {
    final id = newId();
    await db.into(db.fines).insert(FinesCompanion.insert(
        id: id,
        memberId: memberId,
        category: category,
        reason: reason,
        amountPesewas: amountPesewas,
        sessionId: Value(sessionId),
        autoApplied: Value(autoApplied),
        createdBy: db.currentUserId,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('fines', id, SyncOp.insert);
    final dueId = newId();
    await db.into(db.memberDues).insert(MemberDuesCompanion.insert(
        id: dueId,
        memberId: memberId,
        amountPesewas: amountPesewas,
        source: const Value('fine'),
        sourceId: Value(id),
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('member_dues', dueId, SyncOp.insert);
    await db.audit('add_fine', 'fines', id, after: '$category: $reason');
  }

  Stream<List<Fine>> watchFines({FineStatus? status}) {
    var q = db.select(db.fines)..where((f) => f.deletedAt.isNull());
    if (status != null) q = q..where((f) => f.status.equalsValue(status));
    q = q..orderBy([(f) => OrderingTerm(expression: f.createdAt, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<void> setFineStatus(String id, FineStatus status) async {
    await (db.update(db.fines)..where((f) => f.id.equals(id)))
        .write(FinesCompanion(status: Value(status), updatedAt: Value(nowIso())));
    await db.logChange('fines', id, SyncOp.update);
    if (status == FineStatus.waived) {
      final due = await (db.select(db.memberDues)
            ..where((d) => d.sourceId.equals(id) & d.source.equals('fine')))
          .getSingleOrNull();
      if (due != null) {
        await waive(due.id, due.amountPesewas, 'Fine waived');
      }
    }
    await db.audit('fine_${status.name}', 'fines', id);
  }

  Future<List<Category>> categories(CategoryKind kind) =>
      (db.select(db.categories)..where((c) => c.kind.equalsValue(kind) & c.deletedAt.isNull())).get();

  Stream<List<Category>> watchCategories(CategoryKind kind) =>
      (db.select(db.categories)..where((c) => c.kind.equalsValue(kind) & c.deletedAt.isNull())).watch();

  Future<void> saveCategory(CategoriesCompanion c, String id, {required bool isNew}) async {
    await db.into(db.categories).insertOnConflictUpdate(c);
    await db.logChange('categories', id, isNew ? SyncOp.insert : SyncOp.update);
  }

  Stream<List<Expense>> watchExpenses() =>
      (db.select(db.expenses)..where((e) => e.deletedAt.isNull())..orderBy([(e) => OrderingTerm(expression: e.spentAt, mode: OrderingMode.desc)])).watch();

  Future<void> saveExpense(ExpensesCompanion c, String id, {required bool isNew}) async {
    await db.into(db.expenses).insertOnConflictUpdate(c);
    await db.logChange('expenses', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'expenses', id);
  }

  Future<void> softDeleteExpense(String id) async {
    await (db.update(db.expenses)..where((e) => e.id.equals(id)))
        .write(ExpensesCompanion(deletedAt: Value(nowIso()), updatedAt: Value(nowIso())));
    await db.logChange('expenses', id, SyncOp.delete);
    await db.audit('delete', 'expenses', id);
  }

  Future<({int income, int expenses, int net})> termTotals(String termId) async {
    final term = await (db.select(db.terms)..where((t) => t.id.equals(termId))).getSingle();
    final payments = await (db.select(db.payments)
          ..where((p) => p.termId.equals(termId) & p.deletedAt.isNull()))
        .get();
    final income = payments.fold<int>(0, (s, p) => s + p.amountPesewas);
    final expenses = await (db.select(db.expenses)
          ..where((e) =>
              e.deletedAt.isNull() &
              e.spentAt.isBiggerOrEqualValue(term.startDate) &
              e.spentAt.isSmallerOrEqualValue('${term.endDate}T23:59:59')))
        .get();
    final spent = expenses.fold<int>(0, (s, e) => s + e.amountPesewas);
    return (income: income, expenses: spent, net: income - spent);
  }

  Future<double> collectionRate(String termId) async {
    final term = await (db.select(db.terms)..where((t) => t.id.equals(termId))).getSingle();
    final dues = await (db.select(db.memberDues)
          ..where((d) =>
              d.deletedAt.isNull() &
              d.createdAt.isBiggerOrEqualValue(term.startDate) &
              d.createdAt.isSmallerOrEqualValue('${term.endDate}T23:59:59')))
        .get();
    final charged = dues.fold<int>(0, (s, d) => s + d.amountPesewas - d.waiverPesewas);
    if (charged == 0) return 100;
    final totals = await termTotals(termId);
    return (totals.income * 100 / charged).clamp(0, 100);
  }

  Future<List<Defaulter>> defaulters() async {
    final members = await (db.select(db.members)
          ..where((m) =>
              m.deletedAt.isNull() &
              m.status.isInValues([MemberStatus.active, MemberStatus.probation]))
          ..orderBy([(m) => OrderingTerm(expression: m.fullName)]))
        .get();
    final out = <Defaulter>[];
    for (final m in members) {
      final b = await balance(m.id);
      if (b.owing > 0) out.add(Defaulter(m, b.owing));
    }
    out.sort((a, b) => b.owing.compareTo(a.owing));
    return out;
  }

  Stream<List<ActivityLog>> auditTrail() =>
      (db.select(db.activityLogs)
            ..where((l) => l.targetTable.isIn([
                  'payments', 'member_dues', 'payment_allocations', 'fines',
                  'expenses', 'levies'
                ]))
            ..orderBy([(l) => OrderingTerm(expression: l.createdAt, mode: OrderingMode.desc)])
            ..limit(200))
          .watch();
}
// End-to-end DAO smoke test against an in-memory SQLCipher database.
// Run with: dart run tool/smoke_test.dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:winroc_metrics/core/constants.dart';
import 'package:winroc_metrics/core/utils.dart';
import 'package:winroc_metrics/data/daos/admin_dao.dart';
import 'package:winroc_metrics/data/daos/attendance_dao.dart';
import 'package:winroc_metrics/data/daos/finance_dao.dart';
import 'package:winroc_metrics/data/daos/member_dao.dart';
import 'package:winroc_metrics/data/database.dart';
import 'package:winroc_metrics/data/sync_service.dart';

int _passed = 0;

void check(bool cond, String label) {
  if (!cond) throw StateError('FAILED: $label');
  _passed++;
  stdout.writeln('  ok: $label');
}

Future<void> main() async {
  final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
    if (raw.select('PRAGMA cipher_version;').isEmpty) {
      throw StateError('SQLCipher not active in smoke test');
    }
    raw.execute('PRAGMA foreign_keys = ON;');
  }));
  db.deviceId = 'smoke-device';

  final memberDao = MemberDao(db);
  final attendanceDao = AttendanceDao(db);
  final financeDao = FinanceDao(db);
  final adminDao = AdminDao(db);
  final sync = SyncService(db);

  stdout.writeln('== seed ==');
  final term = await (db.select(db.terms)
        ..where((t) => t.isCurrent.equals(true)))
      .getSingle();
  final year = await (db.select(db.academicYears)
        ..where((y) => y.isCurrent.equals(true)))
      .getSingle();
  check(term.number == 1, 'seeded current term is term 1');
  check((await db.setting('currency')) == 'GHS', 'currency defaults to GHS');
  check((await memberDao.allTeams()).length == 4, '4 default teams seeded');

  stdout.writeln('== members ==');
  final m1 = newId();
  final m2 = newId();
  await memberDao.save(
      MembersCompanion.insert(
          id: m1,
          studentId: 'SMOKE-001',
          fullName: 'Test Member One',
          form: 2,
          joinDate: '2026-09-01',
          qrToken: randomSecret(),
          createdAt: nowIso(),
          updatedAt: nowIso()),
      m1,
      isNew: true);
  await memberDao.save(
      MembersCompanion.insert(
          id: m2,
          studentId: 'SMOKE-002',
          fullName: 'Test Member Two',
          form: 3,
          joinDate: '2026-09-01',
          qrToken: randomSecret(),
          createdAt: nowIso(),
          updatedAt: nowIso()),
      m2,
      isNew: true);
  check((await memberDao.activeMembers()).length == 2, '2 active members');
  check(await memberDao.studentIdExists('SMOKE-001'), 'student id lookup');
  check(!await memberDao.studentIdExists('NOPE'), 'missing student id lookup');
  final imported = await memberDao.importRows([
    {'full_name': 'Imported Member', 'student_id': 'SMOKE-003', 'form': '1', 'team': 'Programming'},
    {'full_name': 'Imported Member', 'student_id': 'SMOKE-003', 'form': '1'},
  ]);
  check(imported == 1, 'import dedupes by student id');
  final exported = await memberDao.exportRows();
  check(exported.length == 3, 'export returns all members');

  stdout.writeln('== attendance ==');
  final s1 = newId();
  await attendanceDao.save(
      SessionsCompanion.insert(
          id: s1,
          termId: term.id,
          type: SessionType.regular,
          title: 'Smoke Session',
          date: dateOnly(DateTime.now()),
          startTime: '15:30',
          selfCodeSecret: randomSecret(),
          createdBy: '',
          createdAt: nowIso(),
          updatedAt: nowIso()),
      s1,
      isNew: true);
  await attendanceDao.mark(s1, m1, AttendanceStatus.present,
      checkInAt: DateTime.now());
  await attendanceDao.mark(s1, m2, AttendanceStatus.absent);
  await attendanceDao.mark(s1, m1, AttendanceStatus.late,
      checkInAt: DateTime.now(), reason: 'Bus broke down');
  final rec = await attendanceDao.recordFor(s1, m1);
  check(rec != null && rec.status == AttendanceStatus.late, 'mark updates existing record');
  check((await attendanceDao.editHistory(rec!.id)).length == 1,
      'edit history logged with reason');
  check(await attendanceDao.attendancePct(m1, termId: term.id) == 100,
      'late counts as present (100%)');
  check(await attendanceDao.attendancePct(m2, termId: term.id) == 0,
      'absent is 0%');

  final s2 = newId();
  const secret = 'smoke-secret';
  await attendanceDao.save(
      SessionsCompanion.insert(
          id: s2,
          termId: term.id,
          type: SessionType.workshop,
          title: 'Self Check-in Session',
          date: dateOnly(DateTime.now()),
          startTime: '15:30',
          selfCodeSecret: secret,
          createdBy: '',
          createdAt: nowIso(),
          updatedAt: nowIso()),
      s2,
      isNew: true);
  const bucket = 12345;
  final goodToken = codeToken(secret, bucket);
  check(await attendanceDao.selfCheckin(s2, m2, goodToken, bucket),
      'valid rotating code accepted');
  check(!await attendanceDao.selfCheckin(s2, m1, 'BADTOKEN00', bucket),
      'invalid rotating code rejected');
  final pending = await attendanceDao.recordFor(s2, m1);
  check(pending != null && !pending.verified, 'bad code stored unverified');
  check(await attendanceDao.verifyPending(s2) == 0, 'bad code stays unverified');

  await attendanceDao.submitExcuse(m2, s1, 'Medical appointment');
  final excuse = await (db.select(db.excuses)).getSingle();
  await attendanceDao.reviewExcuse(excuse.id, true, 'Approved by officer');
  final excusedRec = await attendanceDao.recordFor(s1, m2);
  check(excusedRec!.status == AttendanceStatus.excused,
      'approved excuse marks member excused');
  check(await attendanceDao.attendancePct(m2, termId: term.id) == 100,
      'excused sessions excluded from percentage');
  final stats = await attendanceDao.withStats((await attendanceDao.get(s1))!);
  check(stats.late == 1 && stats.excused == 1, 'session stats correct');

  stdout.writeln('== finance ==');
  final levyId = newId();
  await financeDao.saveLevy(
      LeviesCompanion.insert(
          id: levyId,
          name: 'Term 1 Dues',
          amountPesewas: 5000,
          frequency: LevyFrequency.termly,
          termId: Value(term.id),
          createdBy: '',
          createdAt: nowIso(),
          updatedAt: nowIso()),
      levyId,
      isNew: true);
  check(await financeDao.chargeLevy(levyId) == 3, 'levy charged to 3 active members');
  check(await financeDao.chargeLevy(levyId) == 0, 'same-term re-charge blocked');
  var bal = await financeDao.balance(m1);
  check(bal.owing == 5000 && bal.charged == 5000, 'balance shows GHS 50 owing');

  final p1 = await financeDao.recordPayment(
      memberId: m1,
      amountPesewas: 2000,
      method: PaymentMethod.cash,
      termId: term.id);
  check(p1.receiptNo == 'WR-${DateTime.now().year}-0001', 'first receipt number');
  bal = await financeDao.balance(m1);
  check(bal.owing == 3000 && bal.paid == 2000, 'partial payment allocated');
  final p2 = await financeDao.recordPayment(
      memberId: m1,
      amountPesewas: 5000,
      method: PaymentMethod.mtnMomo,
      transactionRef: 'MOMO-TEST-1',
      termId: term.id);
  check(p2.receiptNo == 'WR-${DateTime.now().year}-0002', 'receipt numbers increment');
  bal = await financeDao.balance(m1);
  check(bal.owing == 0 && bal.credit == 2000, 'overpay becomes credit');
  check((await financeDao.paymentByReceipt(p1.receiptNo)) != null,
      'receipt lookup');

  await financeDao.addFine(
      memberId: m1, category: 'Other', reason: 'Smoke fine', amountPesewas: 1000);
  bal = await financeDao.balance(m1);
  check(bal.owing == 1000, 'fine creates a due');
  final fine = await (db.select(db.fines)).getSingle();
  await financeDao.setFineStatus(fine.id, FineStatus.waived);
  bal = await financeDao.balance(m1);
  check(bal.owing == 0, 'waiving fine clears the due');

  final totals = await financeDao.termTotals(term.id);
  check(totals.income == 7000 && totals.net == 7000, 'term totals');
  final defs = await financeDao.defaulters();
  check(defs.length == 2 && defs.first.owing == 5000,
      'defaulters lists unpaid members');
  check((await financeDao.auditTrail().first).isNotEmpty, 'finance audit trail');

  stdout.writeln('== auth ==');
  final admin = await adminDao.createUser(
      displayName: 'Smoke Admin', role: ClubRole.admin, pin: '1234');
  var auth = await adminDao.authenticate(admin.id, '0000');
  check(auth.user == null && auth.error == 'wrong', 'wrong PIN rejected');
  auth = await adminDao.authenticate(admin.id, '1234');
  check(auth.user != null && db.currentUserId == admin.id, 'correct PIN logs in');
  for (var i = 0; i < 5; i++) {
    auth = await adminDao.authenticate(admin.id, '9999');
  }
  check(auth.error == 'locked', '5 failures trigger lockout');
  auth = await adminDao.authenticate(admin.id, '1234');
  check(auth.error == 'locked', 'lockout blocks even correct PIN');

  stdout.writeln('== sync ==');
  final row = (await db.rawRow('members', m1))!;
  final newer = Map<String, dynamic>.from(row)
    ..['full_name'] = 'Remote Name'
    ..['updated_at'] = '2099-01-01T00:00:00.000Z';
  var res = await sync.applyChange(RemoteChange(
      1, 'other-device', 'members', m1, SyncOp.update, newer, newer['updated_at'] as String));
  check(res.name == 'applied', 'LWW applies newer remote change');
  check((await memberDao.get(m1))!.fullName == 'Remote Name', 'remote name applied');
  final stale = Map<String, dynamic>.from((await db.rawRow('members', m1))!)
    ..['full_name'] = 'Stale Name'
    ..['updated_at'] = '2020-01-01T00:00:00.000Z';
  res = await sync.applyChange(RemoteChange(
      2, 'other-device', 'members', m1, SyncOp.update, stale, stale['updated_at'] as String));
  check(res.name == 'skipped', 'LWW skips stale change on unprotected table');
  check((await memberDao.get(m1))!.fullName == 'Remote Name', 'stale change ignored');
  res = await sync.applyChange(RemoteChange(
      3, db.deviceId, 'members', m1, SyncOp.update, newer, '2099-01-01T00:00:00.000Z'));
  check(res.name == 'skipped', 'own-device changes skipped');

  final prow = (await db.rawRow('payments', p1.id))!;
  final premote = Map<String, dynamic>.from(prow)
    ..['notes'] = 'remote note'
    ..['updated_at'] = '2020-01-01T00:00:00.000Z';
  res = await sync.applyChange(RemoteChange(4, 'other-device', 'payments', p1.id,
      SyncOp.update, premote, premote['updated_at'] as String));
  check(res.name == 'conflict', 'protected table conflict recorded');
  final conflicts = await sync.watchConflicts().first;
  check(conflicts.length == 1, 'one pending conflict');
  await sync.resolveConflict(conflicts.first.id, true);
  check((await financeDao.paymentByReceipt(p1.receiptNo))!.notes == 'remote note',
      'resolve use-remote applies remote payload');
  check((await sync.watchConflicts().first).isEmpty, 'conflict cleared');

  stdout.writeln('== promotion ==');
  final promoted = await memberDao.promoteEndOfYear(
      currentYearId: year.id,
      newYearName: '2027/2028',
      newYearStart: '2027-09-01',
      newYearEnd: '2028-07-31',
      termDates: [
        (1, '2027-09-01', '2027-12-17'),
        (2, '2028-01-05', '2028-04-07'),
        (3, '2028-04-24', '2028-07-28'),
      ]);
  check(promoted == 3, 'all active members promoted');
  check((await memberDao.get(m1))!.form == 3, 'form 2 advanced to form 3');
  final grad = await memberDao.get(m2);
  check(grad!.status == MemberStatus.alumni, 'form 3 member graduated to alumni');
  check((await memberDao.history(m1)).length == 1, 'form history recorded');
  final newTerm = await (db.select(db.terms)
        ..where((t) => t.isCurrent.equals(true)))
      .getSingle();
  check(newTerm.startDate == '2027-09-01', 'new year term 1 is current');

  stdout.writeln('== logs ==');
  check((await db.select(db.changeLogs).get()).isNotEmpty, 'change log populated');
  check((await db.select(db.activityLogs).get()).isNotEmpty, 'activity log populated');

  await db.close();
  stdout.writeln('\nSMOKE TEST PASSED ($_passed checks)');
}
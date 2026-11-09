import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../database.dart';

class SessionWithStats {
  final Session session;
  final int present;
  final int late;
  final int excused;
  final int absent;
  final int total;
  SessionWithStats(this.session, this.present, this.late, this.excused, this.absent, this.total);
  int get marked => present + late + excused + absent;
}

class AttendanceDao {
  final AppDatabase db;
  AttendanceDao(this.db);

  Stream<List<Session>> watchSessions({String? termId, bool upcomingOnly = false}) {
    var q = db.select(db.sessions)..where((s) => s.deletedAt.isNull());
    if (termId != null) q = q..where((s) => s.termId.equals(termId));
    if (upcomingOnly) {
      q = q
        ..where((s) => s.date.isBiggerOrEqualValue(dateOnly(DateTime.now())))
        ..where((s) => s.state.equalsValue(SessionState.closed).not());
    }
    q = q..orderBy([(s) => OrderingTerm(expression: s.date, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<Session?> get(String id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<Session?> watch(String id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).watchSingleOrNull();

  Future<void> save(SessionsCompanion c, String id, {required bool isNew}) async {
    final before = isNew ? null : await db.rawRow('sessions', id);
    await db.into(db.sessions).insertOnConflictUpdate(c);
    await db.logChange('sessions', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'sessions', id,
        before: before == null ? null : jsonEncode(before));
  }

  Future<void> setState(String id, SessionState state) async {
    await (db.update(db.sessions)..where((s) => s.id.equals(id)))
        .write(SessionsCompanion(state: Value(state), updatedAt: Value(nowIso())));
    await db.logChange('sessions', id, SyncOp.update);
    await db.audit(state.name, 'sessions', id);
  }

  Stream<List<AttendanceRecord>> watchRecords(String sessionId) =>
      (db.select(db.attendanceRecords)
            ..where((r) => r.sessionId.equals(sessionId) & r.deletedAt.isNull()))
          .watch();

  Future<List<AttendanceRecord>> recordsFor(String sessionId) =>
      (db.select(db.attendanceRecords)
            ..where((r) => r.sessionId.equals(sessionId) & r.deletedAt.isNull()))
          .get();

  Future<AttendanceRecord?> recordFor(String sessionId, String memberId) =>
      (db.select(db.attendanceRecords)
            ..where((r) =>
                r.sessionId.equals(sessionId) &
                r.memberId.equals(memberId) &
                r.deletedAt.isNull()))
          .getSingleOrNull();

  AttendanceStatus statusForCheckin(Session s, DateTime now, int defaultGrace) {
    final start = DateTime.parse('${s.date}T${s.startTime}');
    final grace = s.graceMinutes ?? defaultGrace;
    return now.isAfter(start.add(Duration(minutes: grace)))
        ? AttendanceStatus.late
        : AttendanceStatus.present;
  }

  Future<void> mark(
    String sessionId,
    String memberId,
    AttendanceStatus status, {
    CheckinMethod method = CheckinMethod.manual,
    DateTime? checkInAt,
    String reason = '',
    bool verified = true,
    String? selfToken,
    int? selfBucket,
  }) async {
    final existing = await recordFor(sessionId, memberId);
    final now = nowIso();
    final checkIn = checkInAt?.toUtc().toIso8601String();
    if (existing != null) {
      if (existing.status != status || existing.checkInAt != checkIn) {
        await db.into(db.attendanceEdits).insert(AttendanceEditsCompanion.insert(
            id: newId(),
            attendanceRecordId: existing.id,
            oldStatus: existing.status,
            newStatus: status,
            oldCheckInAt: Value(existing.checkInAt),
            newCheckInAt: Value(checkIn),
            reason: reason.isEmpty ? 'Edited by officer' : reason,
            editedBy: db.currentUserId,
            editedAt: now));
      }
      await (db.update(db.attendanceRecords)
            ..where((r) => r.id.equals(existing.id)))
          .write(AttendanceRecordsCompanion(
              status: Value(status),
              checkInAt: Value(checkIn),
              method: Value(method),
              markedBy: Value(db.currentUserId),
              verified: Value(verified),
              selfToken: Value(selfToken),
              selfBucket: Value(selfBucket),
              updatedAt: Value(now)));
      await db.logChange('attendance_records', existing.id, SyncOp.update);
      await db.audit('mark_attendance', 'attendance_records', existing.id,
          after: '${status.name} ($method)');
    } else {
      final id = newId();
      await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
          id: id,
          sessionId: sessionId,
          memberId: memberId,
          status: status,
          checkInAt: Value(checkIn),
          method: method,
          markedBy: db.currentUserId,
          verified: Value(verified),
          selfToken: Value(selfToken),
          selfBucket: Value(selfBucket),
          createdAt: now,
          updatedAt: now));
      await db.logChange('attendance_records', id, SyncOp.insert);
      await db.audit('mark_attendance', 'attendance_records', id,
          after: '${status.name} ($method)');
    }
  }

  Future<void> markAllPresent(String sessionId, List<String> memberIds, int defaultGrace) async {
    final session = await get(sessionId);
    if (session == null) return;
    final status = statusForCheckin(session, DateTime.now(), defaultGrace);
    for (final id in memberIds) {
      final existing = await recordFor(sessionId, id);
      if (existing == null) {
        await mark(sessionId, id, status, checkInAt: DateTime.now());
      }
    }
  }

  Future<bool> selfCheckin(String sessionId, String memberId, String token, int bucket) async {
    final session = await get(sessionId);
    if (session == null || session.state == SessionState.closed) return false;
    final valid = verifyCodeToken(session.selfCodeSecret, token, bucket);
    final grace = int.tryParse(await db.setting('grace_minutes', fallback: '${Defaults.graceMinutes}')) ?? Defaults.graceMinutes;
    final status = statusForCheckin(session, DateTime.now(), grace);
    await mark(sessionId, memberId, status,
        method: CheckinMethod.selfCode,
        checkInAt: DateTime.now(),
        verified: valid,
        selfToken: token,
        selfBucket: bucket,
        reason: 'Self check-in');
    return valid;
  }

  Future<int> verifyPending(String sessionId) async {
    final session = await get(sessionId);
    if (session == null) return 0;
    final pending = await (db.select(db.attendanceRecords)
          ..where((r) =>
              r.sessionId.equals(sessionId) &
              r.verified.equals(false) &
              r.selfToken.isNotNull()))
        .get();
    var fixed = 0;
    for (final r in pending) {
      if (verifyCodeToken(session.selfCodeSecret, r.selfToken!, r.selfBucket ?? 0)) {
        await (db.update(db.attendanceRecords)..where((t) => t.id.equals(r.id)))
            .write(AttendanceRecordsCompanion(
                verified: const Value(true), updatedAt: Value(nowIso())));
        await db.logChange('attendance_records', r.id, SyncOp.update);
        fixed++;
      }
    }
    return fixed;
  }

  Future<List<AttendanceEdit>> editHistory(String recordId) =>
      (db.select(db.attendanceEdits)
            ..where((e) => e.attendanceRecordId.equals(recordId))
            ..orderBy([(e) => OrderingTerm(expression: e.editedAt, mode: OrderingMode.desc)]))
          .get();

  Future<List<AttendanceRecord>> recordsForMember(String memberId, {String? termId}) async {
    final q = db.select(db.attendanceRecords).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.attendanceRecords.sessionId)),
    ])
      ..where(db.attendanceRecords.memberId.equals(memberId) &
          db.attendanceRecords.deletedAt.isNull() &
          db.sessions.deletedAt.isNull());
    if (termId != null) q.where(db.sessions.termId.equals(termId));
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.attendanceRecords)).toList();
  }

  double pctFrom(List<AttendanceRecord> records) {
    final counted = records.where((r) => r.status != AttendanceStatus.excused).toList();
    if (counted.isEmpty) return 100;
    final present = counted.where((r) => r.status.countsAsPresent).length;
    return present * 100 / counted.length;
  }

  Future<double> attendancePct(String memberId, {String? termId}) async =>
      pctFrom(await recordsForMember(memberId, termId: termId));

  Future<int> streak(String memberId) async {
    final q = db.select(db.attendanceRecords).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.attendanceRecords.sessionId)),
    ])
      ..where(db.attendanceRecords.memberId.equals(memberId) &
          db.attendanceRecords.deletedAt.isNull())
      ..orderBy([OrderingTerm(expression: db.sessions.date, mode: OrderingMode.desc)]);
    final rows = await q.get();
    var streak = 0;
    for (final row in rows) {
      final r = row.readTable(db.attendanceRecords);
      if (r.status == AttendanceStatus.excused) continue;
      if (r.status.countsAsPresent) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  Future<List<({Member member, double pct, int sessions})>> leaderboard(String termId) async {
    final members = await (db.select(db.members)
          ..where((m) => m.deletedAt.isNull() & m.status.equalsValue(MemberStatus.alumni).not()))
        .get();
    final out = <({Member member, double pct, int sessions})>[];
    for (final m in members) {
      final records = await recordsForMember(m.id, termId: termId);
      if (records.isEmpty) continue;
      final pct = pctFrom(records);
      if (pct >= 100) out.add((member: m, pct: pct, sessions: records.length));
    }
    out.sort((a, b) => b.sessions.compareTo(a.sessions));
    return out;
  }

  Future<List<({Member member, double pct})>> atRisk(double threshold, String termId) async {
    final members = await (db.select(db.members)
          ..where((m) =>
              m.deletedAt.isNull() &
              m.status.isInValues([MemberStatus.active, MemberStatus.probation])))
        .get();
    final out = <({Member member, double pct})>[];
    for (final m in members) {
      final records = await recordsForMember(m.id, termId: termId);
      if (records.isEmpty) continue;
      final pct = pctFrom(records);
      if (pct < threshold) out.add((member: m, pct: pct));
    }
    out.sort((a, b) => a.pct.compareTo(b.pct));
    return out;
  }

  Future<List<({String teamName, double pct})>> attendanceByTeam(String termId) async {
    final teams = await (db.select(db.teams)..where((t) => t.deletedAt.isNull())).get();
    final out = <({String teamName, double pct})>[];
    for (final t in teams) {
      final memberIds = await (db.select(db.memberTeams)
            ..where((mt) => mt.teamId.equals(t.id) & mt.deletedAt.isNull()))
          .get();
      if (memberIds.isEmpty) continue;
      var total = 0.0;
      var n = 0;
      for (final mt in memberIds) {
        final records = await recordsForMember(mt.memberId, termId: termId);
        if (records.isEmpty) continue;
        total += pctFrom(records);
        n++;
      }
      if (n > 0) out.add((teamName: t.name, pct: total / n));
    }
    return out;
  }

  Future<List<({String date, double pct})>> trend(String termId) async {
    final sessions = await (db.select(db.sessions)
          ..where((s) => s.termId.equals(termId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm(expression: s.date)]))
        .get();
    final out = <({String date, double pct})>[];
    for (final s in sessions) {
      final records = await recordsFor(s.id);
      if (records.isEmpty) continue;
      out.add((date: s.date, pct: pctFrom(records)));
    }
    return out;
  }

  Future<SessionWithStats> withStats(Session s) async {
    final records = await recordsFor(s.id);
    return SessionWithStats(
      s,
      records.where((r) => r.status == AttendanceStatus.present).length,
      records.where((r) => r.status == AttendanceStatus.late).length,
      records.where((r) => r.status == AttendanceStatus.excused).length,
      records.where((r) => r.status == AttendanceStatus.absent).length,
      records.length,
    );
  }

  Future<void> submitExcuse(String memberId, String sessionId, String reason) async {
    final id = newId();
    await db.into(db.excuses).insert(ExcusesCompanion.insert(
        id: id,
        memberId: memberId,
        sessionId: sessionId,
        reason: reason,
        submittedAt: nowIso(),
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('excuses', id, SyncOp.insert);
    await db.audit('submit_excuse', 'excuses', id);
  }

  Stream<List<Excuse>> watchExcuses({ExcuseStatus? status}) {
    var q = db.select(db.excuses)..where((e) => e.deletedAt.isNull());
    if (status != null) q = q..where((e) => e.status.equalsValue(status));
    q = q..orderBy([(e) => OrderingTerm(expression: e.submittedAt, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<void> reviewExcuse(String id, bool approve, String note) async {
    final excuse = await (db.select(db.excuses)..where((e) => e.id.equals(id))).getSingle();
    await (db.update(db.excuses)..where((e) => e.id.equals(id))).write(ExcusesCompanion(
        status: Value(approve ? ExcuseStatus.approved : ExcuseStatus.rejected),
        reviewedBy: Value(db.currentUserId),
        reviewedAt: Value(nowIso()),
        reviewNote: Value(note),
        updatedAt: Value(nowIso())));
    await db.logChange('excuses', id, SyncOp.update);
    await db.audit(approve ? 'approve_excuse' : 'reject_excuse', 'excuses', id);
    if (approve) {
      await mark(excuse.sessionId, excuse.memberId, AttendanceStatus.excused,
          reason: 'Excuse approved: $note');
    }
  }

  Future<List<SessionResource>> resources(String sessionId) =>
      (db.select(db.sessionResources)
            ..where((r) => r.sessionId.equals(sessionId) & r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
          .get();

  Future<void> addResource(String sessionId, ResourceKind kind, String title, String content) async {
    final id = newId();
    await db.into(db.sessionResources).insert(SessionResourcesCompanion.insert(
        id: id,
        sessionId: sessionId,
        kind: kind,
        title: title,
        contentOrPath: content,
        addedBy: db.currentUserId,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('session_resources', id, SyncOp.insert);
  }
}
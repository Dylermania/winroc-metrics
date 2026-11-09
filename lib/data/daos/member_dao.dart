import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../database.dart';

class MemberDao {
  final AppDatabase db;
  MemberDao(this.db);

  Stream<List<Member>> watchMembers({
    String query = '',
    int? form,
    String? teamId,
    MemberStatus? status,
    String sort = 'name',
    bool includeArchived = false,
  }) {
    var q = db.select(db.members)..where((m) => m.deletedAt.isNull());
    if (!includeArchived) {
      q = q..where((m) => m.status.equalsValue(MemberStatus.alumni).not());
    }
    if (status != null) q = q..where((m) => m.status.equalsValue(status));
    if (form != null) q = q..where((m) => m.form.equals(form));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q = q
        ..where((m) => m.fullName.like(like) | m.studentId.like(like));
    }
    if (teamId != null) {
      final inTeam = db.selectOnly(db.memberTeams)
        ..addColumns([db.memberTeams.memberId])
        ..where(db.memberTeams.teamId.equals(teamId) &
            db.memberTeams.deletedAt.isNull());
      q = q..where((m) => m.id.isInQuery(inTeam));
    }
    q = q..orderBy([
      (m) => OrderingTerm(
          expression: sort == 'form'
              ? m.form
              : sort == 'joined'
                  ? m.joinDate
                  : m.fullName),
    ]);
    return q.watch();
  }

  Future<Member?> get(String id) =>
      (db.select(db.members)..where((m) => m.id.equals(id))).getSingleOrNull();

  Stream<Member?> watch(String id) =>
      (db.select(db.members)..where((m) => m.id.equals(id))).watchSingleOrNull();

  Future<List<Member>> activeMembers() => (db.select(db.members)
        ..where((m) =>
            m.deletedAt.isNull() &
            m.status.isInValues([MemberStatus.active, MemberStatus.probation])))
      .get();

  Future<void> save(MembersCompanion c, String id, {required bool isNew}) async {
    final before = isNew ? null : await db.rawRow('members', id);
    await db.into(db.members).insertOnConflictUpdate(c);
    await db.logChange('members', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'members', id,
        before: before == null ? null : jsonEncode(before),
        after: jsonEncode(await db.rawRow('members', id)));
  }

  Future<void> softDelete(String id) async {
    final before = await db.rawRow('members', id);
    await (db.update(db.members)..where((m) => m.id.equals(id)))
        .write(MembersCompanion(updatedAt: Value(nowIso()), deletedAt: Value(nowIso())));
    await db.logChange('members', id, SyncOp.delete);
    await db.audit('delete', 'members', id, before: jsonEncode(before));
  }

  Future<void> restore(String id) async {
    await (db.update(db.members)..where((m) => m.id.equals(id)))
        .write(MembersCompanion(updatedAt: Value(nowIso()), deletedAt: const Value(null)));
    await db.logChange('members', id, SyncOp.update);
    await db.audit('restore', 'members', id);
  }

  Future<bool> studentIdExists(String studentId, {String? exceptId}) async {
    final q = db.select(db.members)
      ..where((m) => m.studentId.equals(studentId) & m.deletedAt.isNull());
    final rows = await q.get();
    return rows.any((m) => m.id != exceptId);
  }

  Future<List<Team>> allTeams() =>
      (db.select(db.teams)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.name)])).get();

  Stream<List<Team>> watchTeams() =>
      (db.select(db.teams)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();

  Future<List<Team>> teamsFor(String memberId) async {
    final q = db.select(db.teams).join([
      innerJoin(db.memberTeams, db.memberTeams.teamId.equalsExp(db.teams.id)),
    ])
      ..where(db.memberTeams.memberId.equals(memberId) &
          db.memberTeams.deletedAt.isNull() &
          db.teams.deletedAt.isNull());
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.teams)).toList();
  }

  Future<void> setTeams(String memberId, List<String> teamIds) async {
    final existing = await (db.select(db.memberTeams)
          ..where((t) => t.memberId.equals(memberId)))
        .get();
    for (final row in existing) {
      if (!teamIds.contains(row.teamId)) {
        await (db.update(db.memberTeams)..where((t) => t.id.equals(row.id)))
            .write(MemberTeamsCompanion(
                updatedAt: Value(nowIso()), deletedAt: Value(nowIso())));
        await db.logChange('member_teams', row.id, SyncOp.delete);
      }
    }
    for (final teamId in teamIds) {
      final has = existing.any((r) => r.teamId == teamId);
      if (has) {
        await (db.update(db.memberTeams)
              ..where((t) => t.memberId.equals(memberId) & t.teamId.equals(teamId)))
            .write(MemberTeamsCompanion(
                updatedAt: Value(nowIso()), deletedAt: const Value(null)));
        final row = await (db.select(db.memberTeams)
              ..where((t) => t.memberId.equals(memberId) & t.teamId.equals(teamId)))
            .getSingle();
        await db.logChange('member_teams', row.id, SyncOp.update);
      } else {
        final id = newId();
        await db.into(db.memberTeams).insert(MemberTeamsCompanion.insert(
            id: id,
            memberId: memberId,
            teamId: teamId,
            joinedAt: nowIso(),
            createdAt: nowIso(),
            updatedAt: nowIso()));
        await db.logChange('member_teams', id, SyncOp.insert);
      }
    }
    await db.audit('update', 'member_teams', memberId);
  }

  Future<List<Skill>> allSkills() =>
      (db.select(db.skills)..where((s) => s.deletedAt.isNull())).get();

  Future<Map<String, int>> skillsFor(String memberId) async {
    final rows = await (db.select(db.memberSkills)
          ..where((s) => s.memberId.equals(memberId) & s.deletedAt.isNull()))
        .get();
    return {for (final r in rows) r.skillId: r.level};
  }

  Future<void> setSkill(String memberId, String skillId, int level) async {
    final existing = await (db.select(db.memberSkills)
          ..where((s) => s.memberId.equals(memberId) & s.skillId.equals(skillId)))
        .getSingleOrNull();
    final id = existing?.id ?? newId();
    await db.into(db.memberSkills).insertOnConflictUpdate(MemberSkillsCompanion(
        id: Value(id),
        memberId: Value(memberId),
        skillId: Value(skillId),
        level: Value(level),
        createdAt: Value(existing?.createdAt ?? nowIso()),
        updatedAt: Value(nowIso()),
        deletedAt: const Value(null)));
    await db.logChange('member_skills', id, existing == null ? SyncOp.insert : SyncOp.update);
  }

  Future<int> importRows(List<Map<String, String>> rows) async {
    var count = 0;
    final teams = await allTeams();
    for (final row in rows) {
      final name = (row['full_name'] ?? '').trim();
      final studentId = (row['student_id'] ?? '').trim();
      if (name.isEmpty || studentId.isEmpty) continue;
      if (await studentIdExists(studentId)) continue;
      final id = newId();
      final status = MemberStatus.values.firstWhere(
          (s) => s.name.toLowerCase() == (row['status'] ?? '').toLowerCase(),
          orElse: () => MemberStatus.active);
      await db.into(db.members).insert(MembersCompanion.insert(
            id: id,
            studentId: studentId,
            fullName: name,
            form: int.tryParse(row['form'] ?? '1')?.clamp(1, 3) ?? 1,
            house: Value(_nullIfEmpty(row['house'])),
            guardianName: Value(_nullIfEmpty(row['guardian_name'])),
            guardianContact: Value(_nullIfEmpty(row['guardian_contact'])),
            joinDate: _nullIfEmpty(row['join_date']) ?? dateOnly(DateTime.now()),
            status: Value(status),
            qrToken: randomSecret(),
            createdAt: nowIso(),
            updatedAt: nowIso(),
          ));
      await db.logChange('members', id, SyncOp.insert);
      final teamName = (row['team'] ?? '').trim();
      if (teamName.isNotEmpty) {
        var team = teams.where((t) => t.name.toLowerCase() == teamName.toLowerCase()).firstOrNull;
        if (team == null) {
          final tid = newId();
          await db.into(db.teams).insert(TeamsCompanion.insert(
              id: tid, name: teamName, createdAt: nowIso(), updatedAt: nowIso()));
          await db.logChange('teams', tid, SyncOp.insert);
          team = Team(id: tid, name: teamName, description: null, createdAt: nowIso(), updatedAt: nowIso(), deletedAt: null);
          teams.add(team);
        }
        await setTeams(id, [team.id]);
      }
      count++;
    }
    await db.audit('import', 'members', '', after: '$count rows');
    return count;
  }

  Future<List<Map<String, String>>> exportRows({bool includeGuardians = false}) async {
    final members = await (db.select(db.members)
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm(expression: m.fullName)]))
        .get();
    final rows = <Map<String, String>>[];
    for (final m in members) {
      final teams = await teamsFor(m.id);
      rows.add({
        'full_name': m.fullName,
        'student_id': m.studentId,
        'form': '${m.form}',
        'house': m.house ?? '',
        'status': m.status.name,
        'club_role': m.clubRole.name,
        'team': teams.map((t) => t.name).join('; '),
        'join_date': m.joinDate,
        if (includeGuardians) 'guardian_name': m.guardianName ?? '',
        if (includeGuardians) 'guardian_contact': m.guardianContact ?? '',
      });
    }
    await db.audit('export', 'members', '', after: '${rows.length} rows');
    return rows;
  }

  Future<MemberFormHistory?> historyFor(String memberId, String yearId) =>
      (db.select(db.memberFormHistories)
            ..where((h) => h.memberId.equals(memberId) & h.academicYearId.equals(yearId)))
          .getSingleOrNull();

  Future<List<MemberFormHistory>> history(String memberId) =>
      (db.select(db.memberFormHistories)
            ..where((h) => h.memberId.equals(memberId))
            ..orderBy([(h) => OrderingTerm(expression: h.createdAt)]))
          .get();

  Future<int> promoteEndOfYear({
    required String currentYearId,
    required String newYearName,
    required String newYearStart,
    required String newYearEnd,
    required List<(int, String, String)> termDates,
  }) async {
    var promoted = 0;
    await db.transaction(() async {
      final members = await activeMembers();
      for (final m in members) {
        await db.into(db.memberFormHistories).insert(MemberFormHistoriesCompanion.insert(
            id: newId(),
            memberId: m.id,
            academicYearId: currentYearId,
            form: m.form,
            statusThatYear: m.status,
            createdAt: nowIso(),
            updatedAt: nowIso()));
        final graduated = m.form >= 3;
        await (db.update(db.members)..where((t) => t.id.equals(m.id))).write(
            MembersCompanion(
                form: Value(graduated ? 3 : m.form + 1),
                status: Value(graduated ? MemberStatus.alumni : m.status),
                updatedAt: Value(nowIso())));
        await db.logChange('members', m.id, SyncOp.update);
        promoted++;
      }
      await (db.update(db.academicYears)).write(
          AcademicYearsCompanion(isCurrent: const Value(false), updatedAt: Value(nowIso())));
      final yearId = newId();
      await db.into(db.academicYears).insert(AcademicYearsCompanion.insert(
          id: yearId,
          name: newYearName,
          startDate: newYearStart,
          endDate: newYearEnd,
          isCurrent: const Value(true),
          createdAt: nowIso(),
          updatedAt: nowIso()));
      await db.logChange('academic_years', yearId, SyncOp.insert);
      await (db.update(db.terms)).write(TermsCompanion(isCurrent: const Value(false), updatedAt: Value(nowIso())));
      for (final (n, start, end) in termDates) {
        final tid = newId();
        await db.into(db.terms).insert(TermsCompanion.insert(
            id: tid,
            academicYearId: yearId,
            number: n,
            startDate: start,
            endDate: end,
            isCurrent: Value(n == 1),
            createdAt: nowIso(),
            updatedAt: nowIso()));
        await db.logChange('terms', tid, SyncOp.insert);
      }
    });
    await db.audit('promote', 'members', '', after: '$promoted members');
    return promoted;
  }

  static String? _nullIfEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
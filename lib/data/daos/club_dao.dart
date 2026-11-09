import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../database.dart';

class ClubDao {
  final AppDatabase db;
  ClubDao(this.db);

  Stream<List<Project>> watchProjects() =>
      (db.select(db.projects)..where((p) => p.deletedAt.isNull())..orderBy([(p) => OrderingTerm(expression: p.createdAt, mode: OrderingMode.desc)])).watch();

  Future<void> saveProject(ProjectsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.projects).insertOnConflictUpdate(c);
    await db.logChange('projects', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'projects', id);
  }

  Future<List<Member>> projectMembers(String projectId) async {
    final q = db.select(db.members).join([
      innerJoin(db.projectMembers, db.projectMembers.memberId.equalsExp(db.members.id)),
    ])
      ..where(db.projectMembers.projectId.equals(projectId) &
          db.projectMembers.deletedAt.isNull() &
          db.members.deletedAt.isNull());
    return (await q.get()).map((r) => r.readTable(db.members)).toList();
  }

  Future<void> setProjectMembers(String projectId, List<String> memberIds) async {
    final existing = await (db.select(db.projectMembers)..where((p) => p.projectId.equals(projectId))).get();
    for (final row in existing) {
      if (!memberIds.contains(row.memberId)) {
        await (db.update(db.projectMembers)..where((p) => p.id.equals(row.id)))
            .write(ProjectMembersCompanion(deletedAt: Value(nowIso()), updatedAt: Value(nowIso())));
        await db.logChange('project_members', row.id, SyncOp.delete);
      }
    }
    for (final mid in memberIds) {
      final has = existing.any((r) => r.memberId == mid);
      if (has) {
        await (db.update(db.projectMembers)
              ..where((p) => p.projectId.equals(projectId) & p.memberId.equals(mid)))
            .write(ProjectMembersCompanion(deletedAt: const Value(null), updatedAt: Value(nowIso())));
        final row = await (db.select(db.projectMembers)
              ..where((p) => p.projectId.equals(projectId) & p.memberId.equals(mid)))
            .getSingle();
        await db.logChange('project_members', row.id, SyncOp.update);
      } else {
        final id = newId();
        await db.into(db.projectMembers).insert(ProjectMembersCompanion.insert(
            id: id, projectId: projectId, memberId: mid, createdAt: nowIso(), updatedAt: nowIso()));
        await db.logChange('project_members', id, SyncOp.insert);
      }
    }
  }

  Future<void> logHours(String projectId, String memberId, double hours, String note) async {
    final id = newId();
    await db.into(db.projectHours).insert(ProjectHoursCompanion.insert(
        id: id,
        projectId: projectId,
        memberId: memberId,
        workDate: dateOnly(DateTime.now()),
        hours: hours,
        note: Value(note),
        loggedBy: db.currentUserId,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('project_hours', id, SyncOp.insert);
    await db.audit('log_hours', 'project_hours', id, after: '$hours h');
    await checkAutoBadges(memberId);
  }

  Future<double> hoursForMember(String memberId) async {
    final rows = await (db.select(db.projectHours)..where((h) => h.memberId.equals(memberId) & h.deletedAt.isNull())).get();
    return rows.fold<double>(0, (s, h) => s + h.hours);
  }

  Future<double> hoursForProject(String projectId) async {
    final rows = await (db.select(db.projectHours)..where((h) => h.projectId.equals(projectId) & h.deletedAt.isNull())).get();
    return rows.fold<double>(0, (s, h) => s + h.hours);
  }

  Future<List<ProjectHour>> projectHours(String projectId) =>
      (db.select(db.projectHours)..where((h) => h.projectId.equals(projectId) & h.deletedAt.isNull())..orderBy([(h) => OrderingTerm(expression: h.workDate, mode: OrderingMode.desc)])).get();

  Stream<List<InventoryItem>> watchInventory() =>
      (db.select(db.inventoryItems)..where((i) => i.deletedAt.isNull())..orderBy([(i) => OrderingTerm(expression: i.name)])).watch();

  Future<void> saveItem(InventoryItemsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.inventoryItems).insertOnConflictUpdate(c);
    await db.logChange('inventory_items', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'inventory_items', id);
  }

  Future<int> availableQty(String itemId) async {
    final item = await (db.select(db.inventoryItems)..where((i) => i.id.equals(itemId))).getSingle();
    final loans = await (db.select(db.inventoryLoans)
          ..where((l) => l.itemId.equals(itemId) & l.checkedInAt.isNull() & l.deletedAt.isNull()))
        .get();
    return item.totalQty - loans.fold<int>(0, (s, l) => s + l.qty);
  }

  Future<List<InventoryLoan>> openLoans({String? itemId}) {
    var q = db.select(db.inventoryLoans)
      ..where((l) => l.checkedInAt.isNull() & l.deletedAt.isNull());
    if (itemId != null) q = q..where((l) => l.itemId.equals(itemId));
    return q.get();
  }

  Future<void> checkOut(String itemId, String memberId, int qty, String? dueDate) async {
    final id = newId();
    await db.into(db.inventoryLoans).insert(InventoryLoansCompanion.insert(
        id: id,
        itemId: itemId,
        memberId: memberId,
        qty: qty,
        checkedOutAt: nowIso(),
        dueDate: Value(dueDate),
        handledBy: db.currentUserId,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('inventory_loans', id, SyncOp.insert);
    await db.audit('check_out', 'inventory_loans', id);
  }

  Future<void> checkIn(String loanId, String condition) async {
    await (db.update(db.inventoryLoans)..where((l) => l.id.equals(loanId)))
        .write(InventoryLoansCompanion(
            checkedInAt: Value(nowIso()),
            conditionIn: Value(condition),
            updatedAt: Value(nowIso())));
    await db.logChange('inventory_loans', loanId, SyncOp.update);
    await db.audit('check_in', 'inventory_loans', loanId);
  }

  Stream<List<Event>> watchEvents() =>
      (db.select(db.events)..where((e) => e.deletedAt.isNull())..orderBy([(e) => OrderingTerm(expression: e.date, mode: OrderingMode.desc)])).watch();

  Future<void> saveEvent(EventsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.events).insertOnConflictUpdate(c);
    await db.logChange('events', id, isNew ? SyncOp.insert : SyncOp.update);
    await db.audit(isNew ? 'create' : 'update', 'events', id);
  }

  Future<List<Member>> eventAttendees(String eventId) async {
    final q = db.select(db.members).join([
      innerJoin(db.eventAttendees, db.eventAttendees.memberId.equalsExp(db.members.id)),
    ])
      ..where(db.eventAttendees.eventId.equals(eventId) & db.eventAttendees.deletedAt.isNull());
    return (await q.get()).map((r) => r.readTable(db.members)).toList();
  }

  Future<void> setEventAttendees(String eventId, List<String> memberIds) async {
    final existing = await (db.select(db.eventAttendees)..where((e) => e.eventId.equals(eventId))).get();
    for (final mid in memberIds) {
      if (!existing.any((r) => r.memberId == mid)) {
        final id = newId();
        await db.into(db.eventAttendees).insert(EventAttendeesCompanion.insert(
            id: id, eventId: eventId, memberId: mid, createdAt: nowIso(), updatedAt: nowIso()));
        await db.logChange('event_attendees', id, SyncOp.insert);
      }
    }
    for (final row in existing) {
      if (!memberIds.contains(row.memberId)) {
        await (db.update(db.eventAttendees)..where((e) => e.id.equals(row.id)))
            .write(EventAttendeesCompanion(deletedAt: Value(nowIso()), updatedAt: Value(nowIso())));
        await db.logChange('event_attendees', row.id, SyncOp.delete);
      }
    }
  }

  Future<List<Badge>> allBadges() =>
      (db.select(db.badges)..where((b) => b.deletedAt.isNull())).get();

  Future<List<MemberBadge>> badgesFor(String memberId) =>
      (db.select(db.memberBadges)..where((b) => b.memberId.equals(memberId) & b.deletedAt.isNull())).get();

  Future<void> awardBadge(String memberId, String badgeId) async {
    final existing = await (db.select(db.memberBadges)
          ..where((b) => b.memberId.equals(memberId) & b.badgeId.equals(badgeId) & b.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) return;
    final id = newId();
    await db.into(db.memberBadges).insert(MemberBadgesCompanion.insert(
        id: id,
        memberId: memberId,
        badgeId: badgeId,
        awardedAt: nowIso(),
        awardedBy: db.currentUserId,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('member_badges', id, SyncOp.insert);
    await db.audit('award_badge', 'member_badges', id);
  }

  Future<void> checkAutoBadges(String memberId, {double? termPct, bool competitionWin = false}) async {
    final badges = await allBadges();
    Badge? byKey(String key) => badges.where((b) => b.criteriaKey == key).firstOrNull;
    if (termPct != null && termPct >= 100) {
      final b = byKey('perfect_attendance');
      if (b != null) await awardBadge(memberId, b.id);
    }
    if (competitionWin) {
      final b = byKey('competition_winner');
      if (b != null) await awardBadge(memberId, b.id);
    }
    final hours = await hoursForMember(memberId);
    if (hours > 0) {
      final b = byKey('first_build');
      if (b != null) await awardBadge(memberId, b.id);
    }
    if (hours >= 100) {
      final b = byKey('hours_100');
      if (b != null) await awardBadge(memberId, b.id);
    }
  }

  Stream<List<Announcement>> watchAnnouncements() =>
      (db.select(db.announcements)
            ..where((a) => a.deletedAt.isNull())
            ..orderBy([
              (a) => OrderingTerm(expression: a.pinned, mode: OrderingMode.desc),
              (a) => OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc),
            ]))
          .watch();

  Future<void> saveAnnouncement(AnnouncementsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.announcements).insertOnConflictUpdate(c);
    await db.logChange('announcements', id, isNew ? SyncOp.insert : SyncOp.update);
  }

  Future<void> deleteAnnouncement(String id) async {
    await (db.update(db.announcements)..where((a) => a.id.equals(id)))
        .write(AnnouncementsCompanion(deletedAt: Value(nowIso()), updatedAt: Value(nowIso())));
    await db.logChange('announcements', id, SyncOp.delete);
  }

  Stream<List<MessageTemplate>> watchTemplates() =>
      (db.select(db.messageTemplates)..where((t) => t.deletedAt.isNull())).watch();

  Future<void> saveTemplate(MessageTemplatesCompanion c, String id, {required bool isNew}) async {
    await db.into(db.messageTemplates).insertOnConflictUpdate(c);
    await db.logChange('message_templates', id, isNew ? SyncOp.insert : SyncOp.update);
  }
}
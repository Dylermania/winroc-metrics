import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/security.dart';
import '../core/utils.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Users,
  Settings,
  ActivityLogs,
  AcademicYears,
  Terms,
  CalendarPeriods,
  Members,
  Teams,
  MemberTeams,
  MemberFormHistories,
  Skills,
  MemberSkills,
  Sessions,
  AttendanceRecords,
  AttendanceEdits,
  Excuses,
  Levies,
  MemberDues,
  Payments,
  PaymentAllocations,
  Fines,
  Categories,
  Expenses,
  Projects,
  ProjectMembers,
  ProjectHours,
  InventoryItems,
  InventoryLoans,
  Events,
  EventAttendees,
  Badges,
  MemberBadges,
  SessionResources,
  Announcements,
  MessageTemplates,
  Devices,
  ChangeLogs,
  SyncPeers,
  SyncConflicts,
  Backups,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  String currentUserId = '';
  String deviceId = '';

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'winroc.sqlite'));
    final key = await DbKeyStore.loadOrCreate();

    final db = AppDatabase(NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        if (raw.select('PRAGMA cipher_version;').isEmpty) {
          throw StateError('SQLCipher is not available; refusing to open an '
              'unencrypted student database.');
        }
        raw.execute("PRAGMA key = '$key';");
        raw.execute('PRAGMA foreign_keys = ON;');
      },
    ));
    await db.customSelect('SELECT 1').get();
    db.deviceId = await db.setting('device_id', fallback: '');
    if (db.deviceId.isEmpty) {
      db.deviceId = newId();
      await db.setSetting('device_id', db.deviceId);
    }
    return db;
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seed();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // The teamLead role was replaced by the current officer roles.
            await customStatement(
                "UPDATE members SET club_role = 'projectSupervisor' WHERE club_role = 'teamLead'");
            await customStatement(
                "UPDATE users SET role = 'projectSupervisor' WHERE role = 'teamLead'");
          }
        },
      );

  late final Set<String> tableNames =
      allTables.map((t) => t.actualTableName).toSet();

  Future<String> setting(String key, {String fallback = ''}) async {
    final row = await (select(settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value ?? fallback;
  }

  Stream<String> watchSetting(String key, {String fallback = ''}) {
    return (select(settings)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((r) => r?.value ?? fallback);
  }

  Future<void> setSetting(String key, String value) async {
    await into(settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: value));
  }

  Future<Map<String, Object?>?> rawRow(String table, String id) async {
    if (!tableNames.contains(table)) return null;
    final row = await customSelect(
      'SELECT * FROM "$table" WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    return row?.data;
  }

  Future<void> logChange(String table, String id, SyncOp op) async {
    if (!tableNames.contains(table)) return;
    String? payload;
    if (op != SyncOp.delete) {
      final data = await rawRow(table, id);
      payload = data == null ? null : jsonEncode(data);
    }
    await into(changeLogs).insert(ChangeLogsCompanion.insert(
      id: newId(),
      deviceId: deviceId,
      targetTable: table,
      recordId: id,
      op: op,
      payloadJson: Value(payload),
      changedAt: nowIso(),
    ));
  }

  Future<void> audit(String action, String table, String recordId,
      {String? before, String? after}) async {
    await into(activityLogs).insert(ActivityLogsCompanion.insert(
      id: newId(),
      userId: currentUserId,
      action: action,
      targetTable: table,
      recordId: recordId,
      beforeJson: Value(before),
      afterJson: Value(after),
      deviceId: deviceId,
      createdAt: nowIso(),
    ));
  }

  Future<void> _seed() async {
    final now = nowIso();
    Future<void> ins(String table, Insertable row) =>
        into(allTables.firstWhere((t) => t.actualTableName == table)
                as TableInfo<Table, dynamic>)
            .insert(row);

    final defaults = {
      'school_name': Defaults.schoolName,
      'club_name': Defaults.clubName,
      'currency': Defaults.currency,
      'grace_minutes': '${Defaults.graceMinutes}',
      'attendance_threshold': '${Defaults.attendanceThreshold}',
      'auto_lock_minutes': '${Defaults.autoLockMinutes}',
      'late_fine_pesewas': '${Defaults.lateFinePesewas}',
      'theme': 'system',
      'onboarded': '0',
      'auto_backup': '1',
    };
    for (final e in defaults.entries) {
      await ins('settings', SettingsCompanion.insert(key: e.key, value: e.value));
    }

    for (final name in ['Programming', 'Electronics', 'Mechanical', 'Design']) {
      await ins(
          'teams',
          TeamsCompanion.insert(
              id: newId(), name: name, createdAt: now, updatedAt: now));
    }
    for (final name in ['Soldering', 'Arduino', 'CAD', 'Coding', 'Electronics']) {
      await ins(
          'skills',
          SkillsCompanion.insert(
              id: newId(), name: name, createdAt: now, updatedAt: now));
    }
    const badgeDefs = [
      ('First Build', 'Contributed to a first completed build', 'first_build'),
      ('Perfect Attendance', '100% attendance in a term', 'perfect_attendance'),
      ('Competition Winner', 'Won a competition or award', 'competition_winner'),
      ('100 Build Hours', 'Logged 100 project hours', 'hours_100'),
    ];
    for (final (name, desc, key) in badgeDefs) {
      await ins(
          'badges',
          BadgesCompanion.insert(
              id: newId(),
              name: name,
              description: Value(desc),
              criteriaKey: key,
              createdAt: now,
              updatedAt: now));
    }
    const catDefs = [
      (CategoryKind.expense, ['Materials', 'Transport', 'Printing', 'Refreshments', 'Equipment']),
      (CategoryKind.fine, ['Late Attendance', 'Lost Equipment', 'Other']),
      (CategoryKind.duesType, ['Termly Dues', 'Project Levy', 'Event Fee']),
    ];
    for (final (kind, names) in catDefs) {
      for (final name in names) {
        await ins(
            'categories',
            CategoriesCompanion.insert(
                id: newId(),
                kind: kind,
                name: name,
                isDefault: const Value(true),
                createdAt: now,
                updatedAt: now));
      }
    }

    final yearId = newId();
    await ins(
        'academic_years',
        AcademicYearsCompanion.insert(
            id: yearId,
            name: '2026/2027',
            startDate: '2026-09-01',
            endDate: '2027-07-31',
            isCurrent: const Value(true),
            createdAt: now,
            updatedAt: now));
    const termDates = [
      (1, '2026-09-01', '2026-12-18', true),
      (2, '2027-01-05', '2027-04-09', false),
      (3, '2027-04-27', '2027-07-30', false),
    ];
    for (final (n, start, end, current) in termDates) {
      await ins(
          'terms',
          TermsCompanion.insert(
              id: newId(),
              academicYearId: yearId,
              number: n,
              startDate: start,
              endDate: end,
              isCurrent: Value(current),
              createdAt: now,
              updatedAt: now));
    }

    const templates = [
      (TemplateKind.duesReminder,
        'Hello {guardian}, this is a reminder from the {club} at {school}. {name} has an outstanding dues balance of {balance}. Kindly arrange payment. Thank you.'),
      (TemplateKind.guardianSummary,
        'Hello {guardian}, term summary for {name} ({club}, {school}): attendance {attendance_pct}, dues balance {balance}. Thank you for your support.'),
      (TemplateKind.sessionReminder,
        'Reminder: {club} meets on {date} at {time} ({location}). Topic: {title}. Please attend on time.'),
    ];
    for (final (kind, body) in templates) {
      await ins(
          'message_templates',
          MessageTemplatesCompanion.insert(
              id: newId(),
              kind: kind,
              body: body,
              createdAt: now,
              updatedAt: now));
    }
  }
}
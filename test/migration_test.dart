import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winroc_metrics/core/constants.dart';
import 'package:winroc_metrics/core/utils.dart';
import 'package:winroc_metrics/data/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1 teamLead rows migrate to projectSupervisor', () async {
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('PRAGMA foreign_keys = ON;');
    }));
    addTearDown(db.close);
    final now = nowIso();

    await db.customStatement(
        'INSERT INTO members (id, student_id, full_name, form, join_date, club_role, status, qr_token, created_at, updated_at) '
        "VALUES ('m-legacy', 'LEGACY-001', 'Legacy Lead', 2, '2026-09-01', 'teamLead', 'active', 'qr-legacy', '$now', '$now')");
    await db.customStatement(
        'INSERT INTO users (id, display_name, role, pin_hash, pin_salt, created_at, updated_at) '
        "VALUES ('u-legacy', 'Legacy Lead', 'teamLead', 'hash', 'salt', '$now', '$now')");

    // Same statements the v2 onUpgrade runs.
    await db.customStatement(
        "UPDATE members SET club_role = 'projectSupervisor' WHERE club_role = 'teamLead'");
    await db.customStatement(
        "UPDATE users SET role = 'projectSupervisor' WHERE role = 'teamLead'");

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals('m-legacy')))
        .getSingle();
    expect(member.clubRole, ClubRole.projectSupervisor);
    final user = await (db.select(db.users)..where((u) => u.id.equals('u-legacy')))
        .getSingle();
    expect(user.role, ClubRole.projectSupervisor);
  });
}
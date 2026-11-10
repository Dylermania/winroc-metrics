import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/daos/admin_dao.dart';
import 'data/daos/attendance_dao.dart';
import 'data/daos/club_dao.dart';
import 'data/daos/finance_dao.dart';
import 'data/daos/member_dao.dart';
import 'data/database.dart';
import 'data/sync_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) => throw StateError('override in main'));

final memberDaoProvider = Provider((ref) => MemberDao(ref.watch(databaseProvider)));
final attendanceDaoProvider = Provider((ref) => AttendanceDao(ref.watch(databaseProvider)));
final financeDaoProvider = Provider((ref) => FinanceDao(ref.watch(databaseProvider)));
final clubDaoProvider = Provider((ref) => ClubDao(ref.watch(databaseProvider)));
final adminDaoProvider = Provider((ref) => AdminDao(ref.watch(databaseProvider)));
final syncServiceProvider = Provider((ref) => SyncService(ref.watch(databaseProvider)));

final currentUserProvider = StateProvider<User?>((ref) => null);

final currentTermProvider = StreamProvider<Term?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.terms)
        ..where((t) => t.isCurrent.equals(true) & t.deletedAt.isNull())
        ..limit(1))
      .watchSingleOrNull();
});

final currentYearProvider = StreamProvider<AcademicYear?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.academicYears)
        ..where((y) => y.isCurrent.equals(true) & y.deletedAt.isNull())
        ..limit(1))
      .watchSingleOrNull();
});

final allTermsProvider = FutureProvider<List<Term>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.terms)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm(expression: t.startDate, mode: OrderingMode.desc)]))
      .get();
});

final themeModeProvider = StreamProvider<String>((ref) =>
    ref.watch(databaseProvider).watchSetting('theme', fallback: 'system'));

final schoolNameProvider = StreamProvider<String>((ref) =>
    ref.watch(databaseProvider).watchSetting('school_name', fallback: 'Winneba Secondary School'));

final hasUsersProvider = FutureProvider<bool>((ref) async {
  final users = await ref.watch(adminDaoProvider).users();
  return users.isNotEmpty;
});

final onboardedProvider = StreamProvider<String>((ref) =>
    ref.watch(databaseProvider).watchSetting('onboarded', fallback: '0'));
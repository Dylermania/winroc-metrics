import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winroc_metrics/core/constants.dart';
import 'package:winroc_metrics/data/daos/admin_dao.dart';
import 'package:winroc_metrics/data/daos/attendance_dao.dart';
import 'package:winroc_metrics/data/daos/finance_dao.dart';
import 'package:winroc_metrics/data/daos/member_dao.dart';
import 'package:winroc_metrics/data/database.dart';
import 'package:winroc_metrics/features/analytics/analytics_screen.dart';
import 'package:winroc_metrics/features/attendance/attendance_screen.dart';
import 'package:winroc_metrics/features/dashboard/dashboard_screen.dart';
import 'package:winroc_metrics/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('PRAGMA foreign_keys = ON;');
    }));
    db.deviceId = 'widget-test';
    final user = await AdminDao(db)
        .createUser(displayName: 'Test Patron', role: ClubRole.admin, pin: '1234');
    db.currentUserId = user.id;
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      currentUserProvider.overrideWith((ref) => user),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('dashboard renders with empty database', (tester) async {
    await pumpScreen(tester, const DashboardScreen());
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('sessions renders with empty database', (tester) async {
    await pumpScreen(tester, const SessionsScreen());
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('dashboard and sessions render with seeded data', (tester) async {
    final members = MemberDao(db);
    final att = AttendanceDao(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await members.save(
        MembersCompanion.insert(
            id: 'member-1',
            fullName: 'Ama Mensah',
            form: 2,
            studentId: 'WS-0001',
            joinDate: '2026-09-01',
            qrToken: 'qr-token-1',
            createdAt: now,
            updatedAt: now),
        'member-1',
        isNew: true);
    final term = await container.read(currentTermProvider.future);
    final today = DateTime.now();
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await att.save(
        SessionsCompanion.insert(
            id: 'session-1',
            termId: term!.id,
            type: SessionType.regular,
            title: 'Weekly build',
            date: dateStr,
            startTime: '15:30',
            selfCodeSecret: 'secret',
            createdBy: db.currentUserId,
            createdAt: now,
            updatedAt: now),
        'session-1',
        isNew: true);
    await att.mark('session-1', 'member-1', AttendanceStatus.present);

    await pumpScreen(tester, const DashboardScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('1/1'), findsOneWidget);

    await pumpScreen(tester, const SessionsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Weekly build'), findsOneWidget);
  });

  testWidgets('analytics renders both tabs with seeded data', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await MemberDao(db).save(
        MembersCompanion.insert(
            id: 'member-1',
            fullName: 'Ama Mensah',
            form: 2,
            studentId: 'WS-0001',
            joinDate: '2026-09-01',
            qrToken: 'qr-token-1',
            createdAt: now,
            updatedAt: now),
        'member-1',
        isNew: true);
    final term = await container.read(currentTermProvider.future);
    final att = AttendanceDao(db);
    await att.save(
        SessionsCompanion.insert(
            id: 'session-1',
            termId: term!.id,
            type: SessionType.regular,
            title: 'Weekly build',
            date: '2026-11-05',
            startTime: '15:30',
            selfCodeSecret: 'secret',
            createdBy: db.currentUserId,
            createdAt: now,
            updatedAt: now),
        'session-1',
        isNew: true);
    await att.mark('session-1', 'member-1', AttendanceStatus.present);
    final fin = FinanceDao(db);
    await fin.saveLevy(
        LeviesCompanion.insert(
            id: 'levy-1',
            name: 'Term dues',
            amountPesewas: 5000,
            frequency: LevyFrequency.termly,
            createdBy: db.currentUserId,
            createdAt: now,
            updatedAt: now),
        'levy-1',
        isNew: true);
    await fin.chargeLevy('levy-1');
    await fin.recordPayment(
        memberId: 'member-1',
        amountPesewas: 3000,
        method: PaymentMethod.cash,
        termId: term.id);

    await pumpScreen(tester, const AnalyticsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Analytics & Metrics'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);

    await tester.tap(find.text('Dues'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('GHS 30.00'), findsWidgets);
  });
}
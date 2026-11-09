import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/utils.dart';
import '../../data/daos/attendance_dao.dart';
import '../../data/daos/finance_dao.dart';
import '../../data/database.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _notified = {};
  Timer? _timer;
  int _id = 0;

  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      windows: WindowsInitializationSettings(
        appName: 'Winroc Metrics',
        appUserModelId: 'WinneSec.WinrocMetrics',
        guid: 'b7e60d55-3f2a-4c8e-9a1d-52c0e7a41d93',
      ),
    );
    await plugin.initialize(settings);
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> show(String title, String body) async {
    _id++;
    await plugin.show(
      _id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('winroc_reminders', 'Reminders',
            channelDescription: 'Session, dues and attendance reminders',
            importance: Importance.high),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  void startPeriodicChecks(AppDatabase db, AttendanceDao attendance, FinanceDao finance) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _check(db, attendance, finance));
    _check(db, attendance, finance);
  }

  Future<void> _check(AppDatabase db, AttendanceDao attendance, FinanceDao finance) async {
    try {
      final now = DateTime.now();
      final today = dateOnly(now);
      final sessions = await attendance.watchSessions(upcomingOnly: true).first;
      for (final s in sessions) {
        if (s.date != today) continue;
        final start = DateTime.tryParse('${s.date}T${s.startTime}');
        if (start == null) continue;
        final diff = start.difference(now).inMinutes;
        if (diff >= 0 && diff <= 60 && !_notified.contains('session:${s.id}')) {
          _notified.add('session:${s.id}');
          await show('Session soon: ${s.title}', 'Starts at ${s.startTime} today. ${s.location ?? ''}');
        }
      }
      final lastDuesReminder = await db.setting('last_dues_reminder', fallback: '');
      if (lastDuesReminder != today) {
        final defaulters = await finance.defaulters();
        if (defaulters.isNotEmpty) {
          await db.setSetting('last_dues_reminder', today);
          await show('Unpaid dues', '${defaulters.length} member(s) have outstanding dues. Open Dues > Defaulters to send reminders.');
        }
      }
    } catch (_) {
      // Reminders are best-effort; never crash the app over them.
    }
  }

  void dispose() => _timer?.cancel();
}
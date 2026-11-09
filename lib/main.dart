import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'features/communication/reminders.dart';
import 'providers.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  await NotificationService.instance.init();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const WinrocApp(),
  ));
}
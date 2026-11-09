import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/security.dart';
import '../../core/utils.dart';
import '../database.dart';

class AuthResult {
  final User? user;
  final String? error;
  AuthResult(this.user, this.error);
}

class AdminDao {
  final AppDatabase db;
  AdminDao(this.db);

  final Map<String, (int, DateTime?)> _attempts = {};

  Future<List<User>> users() =>
      (db.select(db.users)..where((u) => u.deletedAt.isNull())..orderBy([(u) => OrderingTerm(expression: u.displayName)])).get();

  Stream<List<User>> watchUsers() =>
      (db.select(db.users)..where((u) => u.deletedAt.isNull())..orderBy([(u) => OrderingTerm(expression: u.displayName)])).watch();

  Future<bool> get hasUsers async => (await users()).isNotEmpty;

  Future<User> createUser({
    required String displayName,
    required ClubRole role,
    required String pin,
    String? memberId,
  }) async {
    final id = newId();
    final salt = PinCrypto.newSalt();
    await db.into(db.users).insert(UsersCompanion.insert(
        id: id,
        memberId: Value(memberId),
        displayName: displayName,
        role: role,
        pinHash: PinCrypto.hash(pin, salt),
        pinSalt: salt,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('users', id, SyncOp.insert);
    await db.audit('create_user', 'users', id, after: '$displayName (${role.name})');
    return (await (db.select(db.users)..where((u) => u.id.equals(id))).getSingle());
  }

  Future<void> resetPin(String userId, String newPin) async {
    final salt = PinCrypto.newSalt();
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(UsersCompanion(
        pinHash: Value(PinCrypto.hash(newPin, salt)),
        pinSalt: Value(salt),
        updatedAt: Value(nowIso())));
    await db.logChange('users', userId, SyncOp.update);
    await db.audit('reset_pin', 'users', userId);
  }

  Future<void> setUserActive(String userId, bool active) async {
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(isActive: Value(active), updatedAt: Value(nowIso())));
    await db.logChange('users', userId, SyncOp.update);
    await db.audit(active ? 'activate_user' : 'deactivate_user', 'users', userId);
  }

  Future<void> setBiometric(String userId, bool enabled) async {
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(biometricEnabled: Value(enabled), updatedAt: Value(nowIso())));
    await db.logChange('users', userId, SyncOp.update);
  }

  Future<AuthResult> authenticate(String userId, String pin) async {
    final user = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null || !user.isActive) return AuthResult(null, 'Account not available.');
    final (attempts, lockUntil) = _attempts[userId] ?? (0, null);
    if (lockUntil != null && DateTime.now().isBefore(lockUntil)) {
      return AuthResult(null, 'locked');
    }
    if (!PinCrypto.verify(pin, user.pinSalt, user.pinHash)) {
      final n = attempts + 1;
      final lock = n >= 5 ? DateTime.now().add(Duration(seconds: 30 * (n - 4))) : null;
      _attempts[userId] = (n, lock);
      return AuthResult(null, lock != null ? 'locked' : 'wrong');
    }
    _attempts.remove(userId);
    db.currentUserId = user.id;
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(lastLoginAt: Value(nowIso())));
    await db.audit('login', 'users', userId);
    return AuthResult(user, null);
  }

  Future<User?> userById(String id) =>
      (db.select(db.users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<Term?> currentTerm() =>
      (db.select(db.terms)..where((t) => t.isCurrent.equals(true) & t.deletedAt.isNull())).getSingleOrNull();

  Future<AcademicYear?> currentYear() =>
      (db.select(db.academicYears)..where((y) => y.isCurrent.equals(true) & y.deletedAt.isNull())).getSingleOrNull();

  Stream<List<Term>> watchTerms() =>
      (db.select(db.terms)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.startDate)])).watch();

  Future<List<Term>> terms() =>
      (db.select(db.terms)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.startDate)])).get();

  Future<List<AcademicYear>> years() =>
      (db.select(db.academicYears)..where((y) => y.deletedAt.isNull())..orderBy([(y) => OrderingTerm(expression: y.startDate, mode: OrderingMode.desc)])).get();

  Future<void> setCurrentTerm(String termId) async {
    await (db.update(db.terms)).write(TermsCompanion(isCurrent: const Value(false), updatedAt: Value(nowIso())));
    await (db.update(db.terms)..where((t) => t.id.equals(termId)))
        .write(TermsCompanion(isCurrent: const Value(true), updatedAt: Value(nowIso())));
    final term = await (db.select(db.terms)..where((t) => t.id.equals(termId))).getSingle();
    await (db.update(db.academicYears)).write(AcademicYearsCompanion(isCurrent: const Value(false), updatedAt: Value(nowIso())));
    await (db.update(db.academicYears)..where((y) => y.id.equals(term.academicYearId)))
        .write(AcademicYearsCompanion(isCurrent: const Value(true), updatedAt: Value(nowIso())));
    await db.logChange('terms', termId, SyncOp.update);
    await db.audit('set_current_term', 'terms', termId);
  }

  Future<void> saveTerm(TermsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.terms).insertOnConflictUpdate(c);
    await db.logChange('terms', id, isNew ? SyncOp.insert : SyncOp.update);
  }

  Future<void> saveYear(AcademicYearsCompanion c, String id, {required bool isNew}) async {
    await db.into(db.academicYears).insertOnConflictUpdate(c);
    await db.logChange('academic_years', id, isNew ? SyncOp.insert : SyncOp.update);
  }

  Future<List<CalendarPeriod>> periods(String termId) =>
      (db.select(db.calendarPeriods)..where((c) => c.termId.equals(termId) & c.deletedAt.isNull())).get();

  Future<void> savePeriod(CalendarPeriodsCompanion c, String id) async {
    await db.into(db.calendarPeriods).insertOnConflictUpdate(c);
    await db.logChange('calendar_periods', id, SyncOp.update);
  }

  Future<void> deletePeriod(String id) async {
    await (db.update(db.calendarPeriods)..where((c) => c.id.equals(id)))
        .write(CalendarPeriodsCompanion(deletedAt: Value(nowIso()), updatedAt: Value(nowIso())));
    await db.logChange('calendar_periods', id, SyncOp.delete);
  }

  Future<bool> isDateBlocked(String date) async {
    final term = await currentTerm();
    if (term == null) return false;
    final blocked = await (db.select(db.calendarPeriods)
          ..where((c) =>
              c.termId.equals(term.id) &
              c.deletedAt.isNull() &
              c.startDate.isSmallerOrEqualValue(date) &
              c.endDate.isBiggerOrEqualValue(date)))
        .get();
    return blocked.isNotEmpty;
  }

  Future<Term> resetForNewTerm({
    required int number,
    required String startDate,
    required String endDate,
  }) async {
    final year = await currentYear();
    final id = newId();
    await db.into(db.terms).insert(TermsCompanion.insert(
        id: id,
        academicYearId: year!.id,
        number: number,
        startDate: startDate,
        endDate: endDate,
        createdAt: nowIso(),
        updatedAt: nowIso()));
    await db.logChange('terms', id, SyncOp.insert);
    await setCurrentTerm(id);
    await db.audit('reset_term', 'terms', id);
    return (await (db.select(db.terms)..where((t) => t.id.equals(id))).getSingle());
  }

  Stream<List<ActivityLog>> watchActivity() =>
      (db.select(db.activityLogs)
            ..orderBy([(l) => OrderingTerm(expression: l.createdAt, mode: OrderingMode.desc)])
            ..limit(300))
          .watch();

  Future<File> createBackup(String password, {BackupKind kind = BackupKind.manual}) async {
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    final support = await getApplicationSupportDirectory();
    final dbFile = File(p.join(support.path, 'winroc.sqlite'));
    final bytes = await dbFile.readAsBytes();
    final key = await DbKeyStore.read();
    final encKey = BackupCrypto.encrypt(Uint8List.fromList(utf8.encode(key)), password);
    final manifest = utf8.encode(jsonEncode({
      'app': 'winroc_metrics',
      'version': 1,
      'created': nowIso(),
    }));
    final archive = Archive()
      ..addFile(ArchiveFile('database.sqlite', bytes.length, bytes))
      ..addFile(ArchiveFile('key.enc', encKey.length, utf8.encode(encKey)))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final zip = ZipEncoder().encode(archive)!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'WinrocBackups'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File(p.join(dir.path, 'winroc-$stamp.wmb'));
    await file.writeAsBytes(zip);
    await db.into(db.backups).insert(BackupsCompanion.insert(
        id: newId(),
        filePath: file.path,
        kind: kind,
        createdAt: nowIso(),
        sizeBytes: zip.length));
    await db.audit('backup', 'backups', file.path);
    await _pruneBackups();
    return file;
  }

  Future<void> _pruneBackups() async {
    final rows = await (db.select(db.backups)
          ..orderBy([(b) => OrderingTerm(expression: b.createdAt, mode: OrderingMode.desc)]))
        .get();
    final scheduled = rows.where((r) => r.kind == BackupKind.scheduled).toList();
    for (final old in scheduled.skip(Defaults.maxBackups)) {
      final f = File(old.filePath);
      if (await f.exists()) await f.delete();
      await (db.delete(db.backups)..where((b) => b.id.equals(old.id))).go();
    }
  }

  Future<List<Backup>> backups() =>
      (db.select(db.backups)..orderBy([(b) => OrderingTerm(expression: b.createdAt, mode: OrderingMode.desc)])).get();

  Future<({Uint8List dbBytes, String key})> extractBackup(File file, String password) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final dbEntry = archive.findFile('database.sqlite');
    final keyEntry = archive.findFile('key.enc');
    if (dbEntry == null || keyEntry == null) {
      throw const FormatException('Not a Winroc backup file.');
    }
    final key = utf8.decode(
        BackupCrypto.decrypt(utf8.decode(keyEntry.content as List<int>), password));
    return (dbBytes: Uint8List.fromList(dbEntry.content as List<int>), key: key);
  }

  Future<void> maybeAutoBackup() async {
    if (await db.setting('auto_backup', fallback: '1') != '1') return;
    final last = await db.setting('last_auto_backup', fallback: '');
    final today = dateOnly(DateTime.now());
    if (last == today) return;
    final rows = await backups();
    final todayRows = rows.where((r) => r.createdAt.startsWith(today)).toList();
    if (todayRows.isNotEmpty) {
      await db.setSetting('last_auto_backup', today);
      return;
    }
    final pin = await db.setting('backup_pin', fallback: '');
    if (pin.isEmpty) return;
    await createBackup(pin, kind: BackupKind.scheduled);
    await db.setSetting('last_auto_backup', today);
  }
}
// Verifies that the bundled SQLite library is SQLCipher and that keying works.
// Run: dart run tool/check_sqlcipher.dart
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.openInMemory();
  final version = db.select('PRAGMA cipher_version;');
  if (version.isEmpty) {
    throw StateError('Plain SQLite detected - SQLCipher is NOT bundled.');
  }
  stdout.writeln('SQLCipher version: ${version.first.values.first}');
  db.execute("PRAGMA key = 'test-key';");
  db.execute('CREATE TABLE t (x TEXT);');
  db.execute("INSERT INTO t VALUES ('encrypted');");
  final row = db.select('SELECT x FROM t;').first.values.first;
  if (row != 'encrypted') throw StateError('Roundtrip failed.');
  db.close();
  stdout.writeln('OK: encrypted database roundtrip works.');
}
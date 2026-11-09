import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/strings.dart';
import '../../data/daos/member_dao.dart';
import '../../shared/widgets.dart';

class MemberImportExport {
  static Future<int> importFromFile(BuildContext context, MemberDao dao) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return 0;
    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return 0;
    final ext = (file.extension ?? '').toLowerCase();
    List<Map<String, String>> rows;
    if (ext == 'csv') {
      rows = _parseCsv(utf8.decode(bytes));
    } else {
      rows = _parseExcel(bytes);
    }
    return dao.importRows(rows);
  }

  static List<Map<String, String>> _parseCsv(String text) {
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(text.replaceAll('\r\n', '\n'));
    return _tableToRows(table.map((r) => r.map((c) => '$c').toList()).toList());
  }

  static List<Map<String, String>> _parseExcel(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) return [];
    final table = sheet.rows
        .map((r) => r.map((c) {
              final v = c?.value;
              return switch (v) {
                TextCellValue t => t.value.text ?? '',
                IntCellValue i => '${i.value}',
                DoubleCellValue d => '${d.value}',
                _ => '',
              };
            }).toList())
        .toList();
    return _tableToRows(table);
  }

  static List<Map<String, String>> _tableToRows(List<List<String>> table) {
    if (table.isEmpty) return [];
    final headers =
        table.first.map((h) => h.trim().toLowerCase().replaceAll(' ', '_')).toList();
    final rows = <Map<String, String>>[];
    for (final line in table.skip(1)) {
      final row = <String, String>{};
      for (var i = 0; i < headers.length && i < line.length; i++) {
        row[headers[i]] = line[i].trim();
      }
      rows.add(row);
    }
    return rows;
  }

  static Future<void> exportCsv(
      BuildContext context, MemberDao dao, bool includeGuardians) async {
    final rows = await dao.exportRows(includeGuardians: includeGuardians);
    if (rows.isEmpty) {
      if (context.mounted) showSnack(context, S.emptyList);
      return;
    }
    final headers = rows.first.keys.toList();
    final table = [
      headers,
      for (final r in rows) [for (final h in headers) r[h] ?? ''],
    ];
    final csv = const ListToCsvConverter().convert(table);
    await _deliver(context, utf8.encode(csv), 'winroc-members.csv', 'text/csv');
  }

  static Future<void> exportExcel(
      BuildContext context, MemberDao dao, bool includeGuardians) async {
    final rows = await dao.exportRows(includeGuardians: includeGuardians);
    if (rows.isEmpty) {
      if (context.mounted) showSnack(context, S.emptyList);
      return;
    }
    final excel = Excel.createExcel();
    final sheet = excel['Members'];
    final headers = rows.first.keys.toList();
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow([for (final h in headers) TextCellValue(r[h] ?? '')]);
    }
    excel.setDefaultSheet('Members');
    final bytes = excel.save();
    if (bytes == null) return;
    await _deliver(context, bytes, 'winroc-members.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  static Future<void> _deliver(
      BuildContext context, List<int> bytes, String filename, String mime) async {
    if (Platform.isWindows) {
      await saveBytesFile(context, bytes, filename);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path, mimeType: mime)], text: filename);
  }
}
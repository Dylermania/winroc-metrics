import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

String nowIso() => DateTime.now().toUtc().toIso8601String();

String randomSecret([int bytes = 16]) {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

String formatGhs(int pesewas) =>
    '${Defaults.currency} ${(pesewas / 100).toStringAsFixed(2)}';

int parseGhs(String text) {
  final v = double.tryParse(text.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  return (v * 100).round();
}

String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return DateFormat('EEE, d MMM yyyy').format(d.toLocal());
}

String fmtDateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

String fmtDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return DateFormat('d MMM yyyy, HH:mm').format(d.toLocal());
}

String fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return DateFormat('HH:mm').format(d.toLocal());
}

String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int currentBucket() =>
    DateTime.now().millisecondsSinceEpoch ~/ (Defaults.codeBucketSeconds * 1000);

String codeToken(String secret, int bucket) {
  final mac = Hmac(sha256, utf8.encode(secret));
  final digest = mac.convert(utf8.encode('WINROC:$bucket'));
  return digest.toString().substring(0, 10).toUpperCase();
}

bool verifyCodeToken(String secret, String token, int bucket) {
  for (var b = bucket - 1; b <= bucket + 1; b++) {
    if (codeToken(secret, b) == token.toUpperCase()) return true;
  }
  return false;
}

String memberQrData(String memberId, String qrToken) =>
    'WINROC1:$memberId:$qrToken';

({String memberId, String token})? parseMemberQr(String data) {
  final parts = data.split(':');
  if (parts.length != 3 || parts[0] != 'WINROC1') return null;
  return (memberId: parts[1], token: parts[2]);
}

String sessionCodeData(String sessionId, String token, int bucket) =>
    jsonEncode({'s': sessionId, 't': token, 'b': bucket});

({String sessionId, String token, int bucket})? parseSessionCode(String data) {
  try {
    final m = jsonDecode(data) as Map<String, dynamic>;
    return (
      sessionId: m['s'] as String,
      token: m['t'] as String,
      bucket: (m['b'] as num).toInt(),
    );
  } catch (_) {
    return null;
  }
}

String receiptQrData(String receiptNo, int amountPesewas) =>
    'WINROC-RECEIPT:$receiptNo:$amountPesewas';

String fillTemplate(String body, Map<String, String> values) {
  var out = body;
  values.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
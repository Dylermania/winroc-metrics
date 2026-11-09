import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:winroc_metrics/core/constants.dart';
import 'package:winroc_metrics/core/security.dart';
import 'package:winroc_metrics/core/utils.dart';

void main() {
  group('money', () {
    test('formatGhs formats pesewas as GHS', () {
      expect(formatGhs(2550), 'GHS 25.50');
      expect(formatGhs(0), 'GHS 0.00');
      expect(formatGhs(100000), 'GHS 1000.00');
    });

    test('parseGhs accepts plain and decorated input', () {
      expect(parseGhs('25.50'), 2550);
      expect(parseGhs('GHS 25.50'), 2550);
      expect(parseGhs('1,000.00'), 100000);
      expect(parseGhs('abc'), 0);
    });

    test('roundtrip', () {
      for (final v in [0, 1, 99, 100, 2550, 123456]) {
        expect(parseGhs(formatGhs(v)), v);
      }
    });
  });

  group('rotating session code (TOTP)', () {
    const secret = 'test-secret';
    test('token is deterministic per bucket', () {
      expect(codeToken(secret, 1000), codeToken(secret, 1000));
      expect(codeToken(secret, 1000), isNot(codeToken(secret, 1001)));
      expect(codeToken(secret, 1000).length, 10);
    });

    test('verify accepts current and adjacent buckets only', () {
      final token = codeToken(secret, 5000);
      expect(verifyCodeToken(secret, token, 5000), isTrue);
      expect(verifyCodeToken(secret, token, 4999), isTrue);
      expect(verifyCodeToken(secret, token, 5001), isTrue);
      expect(verifyCodeToken(secret, token, 5002), isFalse);
      expect(verifyCodeToken(secret, token, 4998), isFalse);
    });

    test('verify rejects wrong secret and is case-insensitive', () {
      final token = codeToken(secret, 5000);
      expect(verifyCodeToken('other-secret', token, 5000), isFalse);
      expect(verifyCodeToken(secret, token.toLowerCase(), 5000), isTrue);
    });

    test('session code payload roundtrip', () {
      final data = sessionCodeData('session-1', 'ABC123', 42);
      final parsed = parseSessionCode(data);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, 'session-1');
      expect(parsed.token, 'ABC123');
      expect(parsed.bucket, 42);
      expect(parseSessionCode('not json'), isNull);
      expect(parseSessionCode('{}'), isNull);
    });
  });

  group('member QR', () {
    test('roundtrip', () {
      final data = memberQrData('member-1', 'token-xyz');
      final parsed = parseMemberQr(data);
      expect(parsed, isNotNull);
      expect(parsed!.memberId, 'member-1');
      expect(parsed.token, 'token-xyz');
    });

    test('rejects foreign and malformed codes', () {
      expect(parseMemberQr('https://example.com'), isNull);
      expect(parseMemberQr('WINROC1:only-two'), isNull);
      expect(parseMemberQr('WINROC2:a:b'), isNull);
      expect(parseMemberQr(''), isNull);
    });

    test('receipt QR format', () {
      expect(receiptQrData('WR-2026-0001', 2550), 'WINROC-RECEIPT:WR-2026-0001:2550');
    });
  });

  group('templates and misc', () {
    test('fillTemplate replaces all placeholders', () {
      expect(
        fillTemplate('Dear {name}, you owe {balance}. From {club}.',
            {'name': 'Ama', 'balance': 'GHS 5.00', 'club': 'Winroc'}),
        'Dear Ama, you owe GHS 5.00. From Winroc.',
      );
    });

    test('fillTemplate leaves unknown placeholders intact', () {
      expect(fillTemplate('Hi {name} {unknown}', {'name': 'Kojo'}), 'Hi Kojo {unknown}');
    });

    test('initials', () {
      expect(initials('Ama Mensah'), 'AM');
      expect(initials('Kojo'), 'K');
      expect(initials('  ama   mensah  '), 'AM');
      expect(initials(''), '?');
    });

    test('dateOnly pads', () {
      expect(dateOnly(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('ids are unique', () {
      final ids = List.generate(500, (_) => newId());
      expect(ids.toSet().length, 500);
    });
  });

  group('PIN hashing', () {
    test('verify accepts correct PIN and rejects wrong', () {
      final salt = PinCrypto.newSalt();
      final hash = PinCrypto.hash('1234', salt);
      expect(PinCrypto.verify('1234', salt, hash), isTrue);
      expect(PinCrypto.verify('1235', salt, hash), isFalse);
      expect(PinCrypto.verify('1234', PinCrypto.newSalt(), hash), isFalse);
    });

    test('hash is salted', () {
      expect(PinCrypto.hash('1234', 'salt-a'), isNot(PinCrypto.hash('1234', 'salt-b')));
    });
  });

  group('backup encryption', () {
    test('AES-GCM roundtrip', () {
      final plain = Uint8List.fromList(utf8.encode('secret database key'));
      final enc = BackupCrypto.encrypt(plain, 'correct horse');
      final dec = BackupCrypto.decrypt(enc, 'correct horse');
      expect(dec, plain);
    });

    test('wrong password fails authentication', () {
      final plain = Uint8List.fromList(utf8.encode('secret'));
      final enc = BackupCrypto.encrypt(plain, 'right-password');
      expect(() => BackupCrypto.decrypt(enc, 'wrong-password'), throwsA(anything));
    });

    test('ciphertexts differ for same plaintext (random salt/iv)', () {
      final plain = Uint8List.fromList(utf8.encode('same'));
      expect(BackupCrypto.encrypt(plain, 'pw'), isNot(BackupCrypto.encrypt(plain, 'pw')));
    });
  });

  group('role capabilities', () {
    test('admin can do everything', () {
      for (final c in Capability.values) {
        expect(ClubRole.admin.can(c), isTrue);
      }
    });

    test('member cannot administer or manage finance', () {
      expect(ClubRole.member.can(Capability.admin), isFalse);
      expect(ClubRole.member.can(Capability.finance), isFalse);
    });

    test('treasurer manages finance but not admin', () {
      expect(ClubRole.treasurer.can(Capability.finance), isTrue);
      expect(ClubRole.treasurer.can(Capability.admin), isFalse);
    });
  });
}
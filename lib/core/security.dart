import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';

class DbKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyName = 'winroc_db_key';

  static Future<String> loadOrCreate() async {
    var key = await _storage.read(key: _keyName);
    if (key == null) {
      final r = Random.secure();
      key = List<int>.generate(32, (_) => r.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await _storage.write(key: _keyName, value: key);
    }
    return key;
  }

  static Future<String> read() async => (await _storage.read(key: _keyName))!;

  static Future<void> write(String key) =>
      _storage.write(key: _keyName, value: key);
}

class PinCrypto {
  static String newSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64.encode(bytes);
  }

  static bool verify(String pin, String salt, String expected) =>
      hash(pin, salt) == expected;
}

class BackupCrypto {
  static const _iterations = 50000;

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final deriv = KeyDerivator('SHA-256/HMAC/PBKDF2')
      ..init(Pbkdf2Parameters(salt, _iterations, 32));
    return deriv.process(utf8.encode(password));
  }

  static String encrypt(Uint8List plain, String password) {
    final r = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
    final iv = Uint8List.fromList(List<int>.generate(12, (_) => r.nextInt(256)));
    final key = _deriveKey(password, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final out = cipher.process(plain);
    return base64.encode(salt + iv + out);
  }

  static Uint8List decrypt(String encoded, String password) {
    final bytes = base64.decode(encoded);
    final salt = Uint8List.sublistView(bytes, 0, 16);
    final iv = Uint8List.sublistView(bytes, 16, 28);
    final body = Uint8List.sublistView(bytes, 28);
    final key = _deriveKey(password, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return cipher.process(body);
  }
}

class Biometrics {
  static final _auth = LocalAuthentication();

  static Future<bool> available() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
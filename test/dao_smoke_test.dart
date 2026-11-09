import 'package:flutter_test/flutter_test.dart';

import '../tool/smoke_test.dart' as smoke;

void main() {
  test('DAO end-to-end smoke (SQLCipher in-memory)', () async {
    await smoke.main();
  });
}
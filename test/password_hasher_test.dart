import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/utils/password_hasher.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Reference values computed with Python's hashlib.pbkdf2_hmac.
    test('matches published vector, 1 iteration', () {
      expect(
        hex(PasswordHasher.pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });
    test('matches published vector, 2 iterations', () {
      expect(
        hex(PasswordHasher.pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });
    test('matches published vector, 4096 iterations', () {
      expect(
        hex(PasswordHasher.pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('PasswordHasher', () {
    test('hash then verify succeeds; wrong password fails', () {
      final h = PasswordHasher.hashSync('s3cret', iterations: 1000);
      expect(PasswordHasher.isHashed(h), isTrue);
      expect(h.contains('s3cret'), isFalse);
      expect(PasswordHasher.verifySync('s3cret', h), isTrue);
      expect(PasswordHasher.verifySync('S3cret', h), isFalse);
      expect(PasswordHasher.verifySync('', h), isFalse);
    });

    test('same password gets a different salt and hash each time', () {
      final a = PasswordHasher.hashSync('same', iterations: 1000);
      final b = PasswordHasher.hashSync('same', iterations: 1000);
      expect(a, isNot(b));
      expect(PasswordHasher.verifySync('same', a), isTrue);
      expect(PasswordHasher.verifySync('same', b), isTrue);
    });

    test('unicode (Dari) passwords work', () {
      final h = PasswordHasher.hashSync('رمز‌عبور۱۲۳', iterations: 1000);
      expect(PasswordHasher.verifySync('رمز‌عبور۱۲۳', h), isTrue);
      expect(PasswordHasher.verifySync('رمز‌عبور۱۲۴', h), isFalse);
    });

    test('legacy plain-text passwords still verify', () {
      expect(PasswordHasher.isHashed('1234'), isFalse);
      expect(PasswordHasher.verifySync('1234', '1234'), isTrue);
      expect(PasswordHasher.verifySync('12345', '1234'), isFalse);
    });

    test('malformed hash strings never verify and never throw', () {
      expect(PasswordHasher.verifySync('x', 'pbkdf2-sha256\$abc\$def\$ghi'), isFalse);
      expect(PasswordHasher.verifySync('x', 'pbkdf2-sha256\$1000\$!!\$!!'), isFalse);
    });

    test('needsRehash detects legacy and weaker hashes', () {
      expect(PasswordHasher.needsRehash('plain'), isTrue);
      final weak = PasswordHasher.hashSync('p', iterations: 1000);
      expect(PasswordHasher.needsRehash(weak), isTrue);
      expect(PasswordHasher.needsRehash(weak, iterations: 1000), isFalse);
    });

    test('async hash/verify (background isolate) round-trip', () async {
      final h = await PasswordHasher.hash('bg-pass', iterations: 2000);
      expect(await PasswordHasher.verify('bg-pass', h), isTrue);
      expect(await PasswordHasher.verify('nope', h), isFalse);
    });
  });
}

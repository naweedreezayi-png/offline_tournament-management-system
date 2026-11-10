import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password hashing for tournament locks.
///
/// Algorithm: PBKDF2-HMAC-SHA256 (RFC 8018) with a unique random 16-byte
/// salt per password. This is a dedicated, salted, iterated key-derivation
/// function - not a plain hash. It is used instead of Argon2id because no
/// audited Argon2 package was available to verify offline; PBKDF2 needs only
/// the `crypto` package. Trade-off: PBKDF2 is less resistant to GPU attacks
/// than Argon2id, and [defaultIterations] is lower than the 600,000 OWASP
/// suggests for SHA-256 because this is pure Dart on phones. The iteration
/// count is stored inside every hash, so it can be raised later: [needsRehash]
/// tells the caller to re-hash after a successful login.
///
/// Stored format: `pbkdf2-sha256$<iterations>$<salt base64>$<hash base64>`.
class PasswordHasher {
  PasswordHasher._();

  static const scheme = 'pbkdf2-sha256';
  static const defaultIterations = 100000;
  static const _saltLength = 16;
  static const _keyLength = 32;

  /// True when [stored] is in this class's hashed format (as opposed to a
  /// legacy plain-text password from versions before v34).
  static bool isHashed(String? stored) =>
      stored != null && stored.startsWith('$scheme\$');

  /// Hashes [password] on a background isolate so the UI stays responsive.
  static Future<String> hash(String password, {int iterations = defaultIterations}) =>
      Isolate.run(() => hashSync(password, iterations: iterations));

  /// Verifies [password] against [stored] on a background isolate. A legacy
  /// plain-text [stored] value is compared directly (constant time), so old
  /// tournaments keep working until they are upgraded.
  static Future<bool> verify(String password, String stored) =>
      Isolate.run(() => verifySync(password, stored));

  /// True when [stored] is hashed with fewer iterations than the current
  /// default (or is not hashed at all).
  static bool needsRehash(String stored, {int iterations = defaultIterations}) {
    final parts = _parse(stored);
    return parts == null || parts.iterations < iterations;
  }

  // ---- synchronous implementations (used by tests and the isolate) -----

  static String hashSync(String password,
      {int iterations = defaultIterations, List<int>? salt}) {
    final s = salt ?? _randomSalt();
    final key = pbkdf2Sha256(utf8.encode(password), s, iterations, length: _keyLength);
    return '$scheme\$$iterations\$${base64.encode(s)}\$${base64.encode(key)}';
  }

  static bool verifySync(String password, String stored) {
    final parts = _parse(stored);
    if (parts == null) {
      // Something in our hashed format but unreadable: never accept it.
      if (isHashed(stored)) return false;
      // Legacy plain text.
      return _constantTimeEquals(utf8.encode(password), utf8.encode(stored));
    }
    final key = pbkdf2Sha256(utf8.encode(password), parts.salt, parts.iterations,
        length: parts.hash.length);
    return _constantTimeEquals(key, parts.hash);
  }

  /// PBKDF2 with HMAC-SHA256. Verified against the published test vectors
  /// in test/password_hasher_test.dart.
  static List<int> pbkdf2Sha256(List<int> password, List<int> salt, int iterations,
      {int length = 32}) {
    if (iterations < 1) throw ArgumentError('iterations must be >= 1');
    final mac = Hmac(sha256, password);
    const hLen = 32;
    final blocks = (length + hLen - 1) ~/ hLen;
    final out = <int>[];
    for (var i = 1; i <= blocks; i++) {
      final index = [(i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff];
      var u = mac.convert([...salt, ...index]).bytes;
      final t = List<int>.of(u);
      for (var j = 1; j < iterations; j++) {
        u = mac.convert(u).bytes;
        for (var k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }
      out.addAll(t);
    }
    return out.sublist(0, length);
  }

  static List<int> _randomSalt() {
    final rnd = Random.secure();
    return List<int>.generate(_saltLength, (_) => rnd.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static _Parts? _parse(String stored) {
    if (!isHashed(stored)) return null;
    final p = stored.split('\$');
    if (p.length != 4) return null;
    final it = int.tryParse(p[1]);
    if (it == null || it < 1) return null;
    try {
      return _Parts(it, base64.decode(p[2]), base64.decode(p[3]));
    } catch (_) {
      return null;
    }
  }
}

class _Parts {
  final int iterations;
  final List<int> salt;
  final List<int> hash;
  _Parts(this.iterations, this.salt, this.hash);
}

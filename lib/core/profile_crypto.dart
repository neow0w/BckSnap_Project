import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';

/// Hashing and rules for the profile passwords.
class ProfileCrypto {
  static const int minLength = 6;
  static const int _rounds = 10000;

  static String newSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static void testHash() {
    debugPrint('Flutter test hash: ${hash('test-salt', 'test123')}');
  }

  /// Salted SHA-256, repeated, so a leaked hash is slow to guess.
  static String hash(String salt, String password) {
    List<int> bytes = utf8.encode('$salt:$password');
    for (var i = 0; i < _rounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }

  static String? validate(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Please enter a password';
    if (p.length < minLength) return 'Use at least $minLength characters';
    if (p.length > 64) return 'Password is too long (max 64 characters)';
    return null;
  }
}

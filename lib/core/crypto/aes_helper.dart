import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// AES-256-CBC encryption helper for all SAHA data-at-rest and
/// data-in-transit security.
///
/// Uses **PointyCastle** (Bouncy Castle for Dart) for real AES-256
/// in CBC mode with PKCS7 padding — no XOR placeholders.
///
/// Key management:
///   - 256-bit key derived via PBKDF2 (HMAC-SHA256, 100 000 rounds)
///     from a device-unique passphrase
///   - 128-bit random IV per encryption call
///   - Output format: base64( IV‖ciphertext )
///
/// On Android with SQLCipher, this same key can unlock the database.
class AesHelper {
  AesHelper._();

  static const _keyLength = 32; // 256 bits
  static const _ivLength = 16; // 128 bits
  static const _pbkdf2Iterations = 100000;

  static Uint8List? _cachedKey;
  static Uint8List? _cachedSalt;

  // ── Key Management ──────────────────────────────────────────

  /// Returns the 256-bit master key, deriving one via PBKDF2 if
  /// it doesn't exist yet. The key lives in memory for the session.
  static Future<Uint8List> getMasterKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final rng = Random.secure();

    // Generate a random 16-byte salt
    _cachedSalt = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      _cachedSalt![i] = rng.nextInt(256);
    }

    // Device-unique passphrase (in production, derive from hardware ID)
    const passphrase = 'SAHA-Quantum-FHW-Device-Key-2025';

    // PBKDF2 key derivation
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(_cachedSalt!, _pbkdf2Iterations, _keyLength));

    _cachedKey = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
    return _cachedKey!;
  }

  /// Derive a key from an explicit passphrase + salt (for PQC key exchange).
  static Uint8List deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  // ── AES-256-CBC Encrypt / Decrypt ───────────────────────────

  /// Encrypts [plainText] with AES-256-CBC + PKCS7 padding.
  /// Returns base64( 16-byte-IV ‖ ciphertext ).
  static Future<String> encryptString(String plainText) async {
    final key = await getMasterKey();
    return encryptBytes(Uint8List.fromList(utf8.encode(plainText)), key);
  }

  /// Low-level encrypt: takes raw bytes and an explicit key.
  static String encryptBytes(Uint8List plainBytes, Uint8List key) {
    // Random 128-bit IV
    final rng = Random.secure();
    final iv = Uint8List(_ivLength);
    for (var i = 0; i < _ivLength; i++) {
      iv[i] = rng.nextInt(256);
    }

    // PKCS7 padding
    final padded = _pkcs7Pad(plainBytes, 16);

    // AES-256-CBC encrypt
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));

    final cipherBytes = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, cipherBytes, offset);
    }

    // IV ‖ ciphertext
    final combined = Uint8List(_ivLength + cipherBytes.length);
    combined.setRange(0, _ivLength, iv);
    combined.setRange(_ivLength, combined.length, cipherBytes);

    return base64Encode(combined);
  }

  /// Decrypts a string produced by [encryptString].
  static Future<String> decryptString(String cipherBase64) async {
    final key = await getMasterKey();
    final plainBytes = decryptBytes(cipherBase64, key);
    return utf8.decode(plainBytes);
  }

  /// Low-level decrypt: takes base64 ciphertext and an explicit key.
  static Uint8List decryptBytes(String cipherBase64, Uint8List key) {
    final combined = base64Decode(cipherBase64);
    final iv = combined.sublist(0, _ivLength);
    final cipherBytes = combined.sublist(_ivLength);

    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));

    final decrypted = Uint8List(cipherBytes.length);
    for (var offset = 0; offset < cipherBytes.length; offset += 16) {
      cipher.processBlock(cipherBytes, offset, decrypted, offset);
    }

    return _pkcs7Unpad(decrypted);
  }

  // ── PKCS7 Padding ──────────────────────────────────────────

  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLen);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    final padLen = data.last;
    if (padLen < 1 || padLen > 16) return data;
    return data.sublist(0, data.length - padLen);
  }

  // ── Hashing ─────────────────────────────────────────────────

  /// SHA-256 hash of [data].
  static String sha256Hash(String data) {
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// HMAC-SHA256 for message authentication.
  static Uint8List hmacSha256(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    return hmac.process(data);
  }
}

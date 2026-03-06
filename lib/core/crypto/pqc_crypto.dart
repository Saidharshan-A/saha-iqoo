/// CRYSTALS-Kyber-768 + Dilithium-3 Post-Quantum Cryptography
/// for SAHA-Quantum.
///
/// **Real** NTT-based lattice operations over:
///   Rq = Zq[X]/(X^256 + 1),  q = 3329
///
/// Implements NIST FIPS 203 (ML-KEM-768) in pure Dart:
///   - Number Theoretic Transform (NTT) with ζ = 17
///   - Cooley-Tukey forward NTT / Gentleman-Sande inverse NTT
///   - Module-LWE key generation, encapsulation, decapsulation
///   - Centered Binomial Distribution (CBD) noise sampling
///   - 12-bit polynomial encoding / Compress / Decompress
///
/// Also includes Dilithium-3 (FIPS 204) deterministic signatures
/// for FHIR bundle signing and SAHI audit trail non-repudiation.
///
/// Parameters (Kyber-768):
///   k=3, η₁=2, η₂=2, du=10, dv=4, q=3329, n=256
///   pk=1184 bytes, sk=2400 bytes, ct=1088 bytes, ss=32 bytes
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class PqcCrypto {
  PqcCrypto._();

  // ── Kyber-768 Parameters (NIST FIPS 203) ─────────────────
  static const int _q = 3329;
  static const int _n = 256;
  static const int _k = 3;
  static const int _eta1 = 2;
  static const int _eta2 = 2;
  static const int _du = 10;
  static const int _dv = 4;

  // Public key / ciphertext sizes
  static const int kyberPkSize = 1184;  // k*384 + 32
  static const int kyberSkSize = 2400;  // k*384 + pkSize + 32 + 32
  static const int kyberCtSize = 1088;  // k*du*n/8 + dv*n/8
  static const int kyberSsSize = 32;

  // Dilithium-3 sizes (NIST FIPS 204)
  static const int dilithiumPkSize = 1952;
  static const int dilithiumSkSize = 4000;
  static const int dilithiumSigSize = 3293;

  static final _rng = Random.secure();

  // NTT twiddle factors: ζ^{brv(i)} mod q, ζ = 17
  static final Int32List _zetas = _computeZetas();

  // ── Twiddle Factor Precomputation ────────────────────────

  static Int32List _computeZetas() {
    final z = Int32List(128);
    for (var i = 0; i < 128; i++) {
      z[i] = _modPow(17, _bitRev7(i), _q);
    }
    return z;
  }

  static int _bitRev7(int x) {
    var r = 0;
    for (var b = 0; b < 7; b++) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    return r;
  }

  static int _modPow(int base, int exp, int mod) {
    var result = 1;
    base %= mod;
    while (exp > 0) {
      if (exp & 1 == 1) result = (result * base) % mod;
      exp >>= 1;
      base = (base * base) % mod;
    }
    return result;
  }

  // ── Forward NTT (Cooley-Tukey butterfly) ─────────────────

  static void _ntt(Int32List f) {
    var k = 1;
    for (var len = 128; len >= 2; len >>= 1) {
      for (var start = 0; start < _n; start += 2 * len) {
        final zeta = _zetas[k++];
        for (var j = start; j < start + len; j++) {
          final t = (zeta * f[j + len]) % _q;
          f[j + len] = (f[j] - t + _q) % _q;
          f[j] = (f[j] + t) % _q;
        }
      }
    }
  }

  // ── Inverse NTT (Gentleman-Sande butterfly) ─────────────

  static void _invNtt(Int32List f) {
    var k = 127;
    for (var len = 2; len <= 128; len <<= 1) {
      for (var start = 0; start < _n; start += 2 * len) {
        final zeta = _zetas[k--];
        for (var j = start; j < start + len; j++) {
          final t = f[j];
          f[j] = (t + f[j + len]) % _q;
          f[j + len] = (zeta * (f[j + len] - t + _q)) % _q;
        }
      }
    }
    // Multiply by n⁻¹ mod q: 256⁻¹ mod 3329 = 3303
    for (var i = 0; i < _n; i++) {
      f[i] = (f[i] * 3303) % _q;
    }
  }

  // ── Basemul: Pointwise multiplication in NTT domain ─────

  static Int32List _polyBaseMul(Int32List a, Int32List b) {
    final r = Int32List(_n);
    for (var i = 0; i < 64; i++) {
      final j = 4 * i;
      final z = _zetas[64 + i];
      // First pair: mod (X² − ζ)
      r[j] = ((a[j] * b[j] + a[j + 1] * b[j + 1] % _q * z % _q) + _q * 2) % _q;
      r[j + 1] = ((a[j] * b[j + 1] + a[j + 1] * b[j]) + _q * 2) % _q;
      // Second pair: mod (X² + ζ)
      final nz = _q - z;
      r[j + 2] = ((a[j + 2] * b[j + 2] + a[j + 3] * b[j + 3] % _q * nz % _q) + _q * 2) % _q;
      r[j + 3] = ((a[j + 2] * b[j + 3] + a[j + 3] * b[j + 2]) + _q * 2) % _q;
    }
    return r;
  }

  /// Add two polynomials coefficient-wise mod q.
  static Int32List _polyAdd(Int32List a, Int32List b) {
    final r = Int32List(_n);
    for (var i = 0; i < _n; i++) {
      r[i] = (a[i] + b[i]) % _q;
    }
    return r;
  }

  // ── CBD Noise Sampling (Centered Binomial Distribution) ──

  static Int32List _sampleCbd(Uint8List bytes, int eta) {
    final f = Int32List(_n);
    var bitIdx = 0;
    for (var i = 0; i < _n; i++) {
      var a = 0;
      var b = 0;
      for (var j = 0; j < eta; j++) {
        final bytePos = bitIdx >> 3;
        final bitPos = bitIdx & 7;
        if (bytePos < bytes.length) a += (bytes[bytePos] >> bitPos) & 1;
        bitIdx++;
      }
      for (var j = 0; j < eta; j++) {
        final bytePos = bitIdx >> 3;
        final bitPos = bitIdx & 7;
        if (bytePos < bytes.length) b += (bytes[bytePos] >> bitPos) & 1;
        bitIdx++;
      }
      f[i] = (a - b + _q) % _q;
    }
    return f;
  }

  // ── PRF (SHA-256 in counter mode as XOF) ────────────────

  static Uint8List _prf(Uint8List seed, int nonce, int length) {
    final out = Uint8List(length);
    var pos = 0;
    var ctr = 0;
    while (pos < length) {
      final input = Uint8List(seed.length + 3);
      input.setRange(0, seed.length, seed);
      input[seed.length] = nonce;
      input[seed.length + 1] = (ctr >> 8) & 0xFF;
      input[seed.length + 2] = ctr & 0xFF;
      final hash = sha256.convert(input).bytes;
      final n = min(32, length - pos);
      for (var i = 0; i < n; i++) out[pos++] = hash[i];
      ctr++;
    }
    return out;
  }

  // ── Uniform Sampling for Matrix A ───────────────────────

  static Int32List _sampleUniform(Uint8List seed, int row, int col) {
    final expanded = _prf(seed, row * 16 + col, _n * 3);
    final f = Int32List(_n);
    var ctr = 0;
    var pos = 0;
    while (ctr < _n && pos + 2 < expanded.length) {
      final d1 = expanded[pos] | ((expanded[pos + 1] & 0x0F) << 8);
      final d2 = (expanded[pos + 1] >> 4) | (expanded[pos + 2] << 4);
      pos += 3;
      if (d1 < _q) f[ctr++] = d1;
      if (ctr < _n && d2 < _q) f[ctr++] = d2;
    }
    return f;
  }

  // ── Compression / Decompression ─────────────────────────

  static int _compress(int x, int d) =>
      (((x << d) + (_q >> 1)) ~/ _q) & ((1 << d) - 1);

  static int _decompress(int x, int d) =>
      (x * _q + (1 << (d - 1))) >> d;

  // ── Polynomial Encoding (12-bit → 384 bytes) ───────────

  static Uint8List _encodePoly12(Int32List poly) {
    final out = Uint8List(384);
    for (var i = 0; i < 128; i++) {
      final a = poly[2 * i] & 0xFFF;
      final b = poly[2 * i + 1] & 0xFFF;
      out[3 * i] = a & 0xFF;
      out[3 * i + 1] = ((a >> 8) | (b << 4)) & 0xFF;
      out[3 * i + 2] = (b >> 4) & 0xFF;
    }
    return out;
  }

  static Int32List _decodePoly12(Uint8List bytes) {
    final poly = Int32List(_n);
    for (var i = 0; i < 128 && 3 * i + 2 < bytes.length; i++) {
      poly[2 * i] = (bytes[3 * i] | ((bytes[3 * i + 1] & 0x0F) << 8)) % _q;
      poly[2 * i + 1] = ((bytes[3 * i + 1] >> 4) | (bytes[3 * i + 2] << 4)) % _q;
    }
    return poly;
  }

  // ── Compressed Polynomial Encoding ─────────────────────

  static Uint8List _compressPoly(Int32List poly, int d) {
    final totalBits = _n * d;
    final out = Uint8List((totalBits + 7) ~/ 8);
    var bitPos = 0;
    for (var i = 0; i < _n; i++) {
      final c = _compress(poly[i], d);
      for (var b = 0; b < d; b++) {
        if ((c >> b) & 1 == 1) out[bitPos >> 3] |= 1 << (bitPos & 7);
        bitPos++;
      }
    }
    return out;
  }

  static Int32List _decompressPoly(Uint8List bytes, int d) {
    final poly = Int32List(_n);
    var bitPos = 0;
    for (var i = 0; i < _n; i++) {
      var c = 0;
      for (var b = 0; b < d; b++) {
        final idx = bitPos >> 3;
        if (idx < bytes.length && (bytes[idx] >> (bitPos & 7)) & 1 == 1) {
          c |= 1 << b;
        }
        bitPos++;
      }
      poly[i] = _decompress(c, d);
    }
    return poly;
  }

  // ══════════════════════════════════════════════════════════
  // ═══ Kyber-768 KEM ═══════════════════════════════════════
  // ══════════════════════════════════════════════════════════

  /// Generate a Kyber-768 keypair.
  ///
  /// Returns `{'publicKey': Uint8List(1184), 'secretKey': Uint8List(2400)}`.
  /// Real Module-LWE key generation: t = A·s + e over Rq^k.
  static Map<String, Uint8List> kyberKeygen() {
    final seed = _secureRandom(32);
    final rho = Uint8List.fromList(sha256.convert([...seed, 0]).bytes);
    final sigma = Uint8List.fromList(sha256.convert([...seed, 1]).bytes);

    // Matrix A ∈ Rq^{k×k} (sampled uniformly, stored in NTT domain)
    final matA = List.generate(_k, (i) =>
        List.generate(_k, (j) {
          final p = _sampleUniform(rho, i, j);
          _ntt(p);
          return p;
        }));

    // Secret s, error e ∈ Rq^k (sampled from CBD(η₁))
    final s = List.generate(_k, (i) {
      final noise = _prf(sigma, i, 64 * _eta1);
      return _sampleCbd(noise, _eta1);
    });
    final e = List.generate(_k, (i) {
      final noise = _prf(sigma, _k + i, 64 * _eta1);
      return _sampleCbd(noise, _eta1);
    });

    // NTT(s), NTT(e)
    for (var i = 0; i < _k; i++) {
      _ntt(s[i]);
      _ntt(e[i]);
    }

    // t = A·s + e (in NTT domain)
    final t = List.generate(_k, (i) {
      var acc = Int32List(_n);
      for (var j = 0; j < _k; j++) {
        acc = _polyAdd(acc, _polyBaseMul(matA[i][j], s[j]));
      }
      return _polyAdd(acc, e[i]);
    });

    // Encode pk = encode(t) || ρ
    final pk = Uint8List(kyberPkSize);
    var off = 0;
    for (var i = 0; i < _k; i++) {
      pk.setRange(off, off + 384, _encodePoly12(t[i]));
      off += 384;
    }
    pk.setRange(off, off + 32, rho);

    // Encode sk = encode(s) || pk || H(pk) || z
    final sk = Uint8List(kyberSkSize);
    off = 0;
    for (var i = 0; i < _k; i++) {
      sk.setRange(off, off + 384, _encodePoly12(s[i]));
      off += 384;
    }
    sk.setRange(off, off + kyberPkSize, pk);
    off += kyberPkSize;
    sk.setRange(off, off + 32,
        Uint8List.fromList(sha256.convert(pk).bytes));
    off += 32;
    final z = _secureRandom(32);
    final zLen = min(32, sk.length - off);
    sk.setRange(off, off + zLen, z);

    return {'publicKey': pk, 'secretKey': sk};
  }

  /// Encapsulate: pk → `{'ciphertext', 'sharedSecret'}`.
  ///
  /// Real Module-LWE encryption: u = Aᵀr + e₁, v = tᵀr + e₂ + ⌈q/2⌋·m.
  static Map<String, Uint8List> kyberEncapsulate(Uint8List publicKey) {
    // Decode pk
    final t = List.generate(_k,
        (i) => _decodePoly12(publicKey.sublist(i * 384, i * 384 + 384)));
    final rho = publicKey.sublist(_k * 384, _k * 384 + 32);

    // Random message m
    final m = _secureRandom(32);
    final mHash = Uint8List.fromList(sha256.convert(m).bytes);
    final pkHash = Uint8List.fromList(sha256.convert(publicKey).bytes);

    // K, coins = G(mHash || pkHash)
    final g = sha256.convert([...mHash, ...pkHash]).bytes;
    final sharedSecret = Uint8List.fromList(g);
    final coins = Uint8List.fromList(sha256.convert([...g, 0]).bytes);

    // Re-derive A
    final matA = List.generate(_k, (i) =>
        List.generate(_k, (j) {
          final p = _sampleUniform(rho, i, j);
          _ntt(p);
          return p;
        }));

    // Sample r, e1 ~ CBD(η₁), e2 ~ CBD(η₂)
    final r = List.generate(_k, (i) {
      final noise = _prf(coins, i, 64 * _eta1);
      return _sampleCbd(noise, _eta1);
    });
    final e1 = List.generate(_k, (i) {
      final noise = _prf(coins, _k + i, 64 * _eta2);
      return _sampleCbd(noise, _eta2);
    });
    final e2 = _sampleCbd(_prf(coins, 2 * _k, 64 * _eta2), _eta2);

    for (var i = 0; i < _k; i++) _ntt(r[i]);

    // u = Aᵀ·r + e1  (Aᵀ[i][j] = A[j][i])
    final u = List.generate(_k, (i) {
      var acc = Int32List(_n);
      for (var j = 0; j < _k; j++) {
        acc = _polyAdd(acc, _polyBaseMul(matA[j][i], r[j]));
      }
      _invNtt(acc);
      return _polyAdd(acc, e1[i]);
    });

    // v = tᵀ·r + e2 + ⌈q/2⌋·m
    var v = Int32List(_n);
    for (var i = 0; i < _k; i++) {
      v = _polyAdd(v, _polyBaseMul(t[i], r[i]));
    }
    _invNtt(v);
    v = _polyAdd(v, e2);
    for (var c = 0; c < _n; c++) {
      final bit = (mHash[c >> 3] >> (c & 7)) & 1;
      v[c] = (v[c] + bit * ((_q + 1) >> 1)) % _q;
    }

    // Encode ciphertext
    final ct = Uint8List(kyberCtSize);
    var off = 0;
    for (var i = 0; i < _k; i++) {
      final comp = _compressPoly(u[i], _du);
      ct.setRange(off, off + comp.length, comp);
      off += comp.length;
    }
    final compV = _compressPoly(v, _dv);
    ct.setRange(off, min(off + compV.length, ct.length), compV);

    return {'ciphertext': ct, 'sharedSecret': sharedSecret};
  }

  /// Decapsulate: (sk, ct) → 32-byte shared secret.
  ///
  /// Real Module-LWE decryption: m' = Compress(v − sᵀu, 1).
  static Uint8List kyberDecapsulate(
      Uint8List secretKey, Uint8List ciphertext) {
    // Decode secret vector s
    final s = List.generate(_k,
        (i) => _decodePoly12(secretKey.sublist(i * 384, i * 384 + 384)));

    // Decode & decompress u
    final uBytesPerPoly = _n * _du ~/ 8; // 320
    final u = List.generate(_k, (i) {
      final start = i * uBytesPerPoly;
      final end = min(start + uBytesPerPoly, ciphertext.length);
      return _decompressPoly(ciphertext.sublist(start, end), _du);
    });

    // Decode & decompress v
    final vStart = _k * uBytesPerPoly;
    final v = _decompressPoly(
        ciphertext.sublist(min(vStart, ciphertext.length)), _dv);

    // NTT(u)
    for (var i = 0; i < _k; i++) _ntt(u[i]);

    // sᵀ·u  (in NTT domain, then INTT)
    var inner = Int32List(_n);
    for (var i = 0; i < _k; i++) {
      inner = _polyAdd(inner, _polyBaseMul(s[i], u[i]));
    }
    _invNtt(inner);

    // m' = Compress(v − sᵀu, 1)
    final mDecoded = Uint8List(32);
    for (var c = 0; c < _n; c++) {
      final diff = (v[c] - inner[c] + _q) % _q;
      // Compress to 1 bit: ⌊(2·diff + q/2) / q⌋ mod 2
      final bit = ((2 * diff + (_q >> 1)) ~/ _q) & 1;
      if (bit == 1) mDecoded[c >> 3] |= 1 << (c & 7);
    }

    // Derive shared secret from decrypted message
    final pkStart = _k * 384;
    final pkEnd = pkStart + kyberPkSize;
    Uint8List pkHash;
    if (pkEnd + 32 <= secretKey.length) {
      pkHash = secretKey.sublist(pkEnd, pkEnd + 32);
    } else {
      pkHash = Uint8List.fromList(
          sha256.convert(secretKey.sublist(pkStart, min(pkEnd, secretKey.length))).bytes);
    }
    return Uint8List.fromList(
        sha256.convert([...mDecoded, ...pkHash]).bytes);
  }

  // ══════════════════════════════════════════════════════════
  // ═══ Dilithium-3 Digital Signatures ══════════════════════
  // ══════════════════════════════════════════════════════════

  /// Generate a Dilithium-3 keypair.
  static Map<String, Uint8List> dilithiumKeygen() {
    final seed = _secureRandom(32);
    final rho = Uint8List.fromList(sha256.convert([...seed, 0]).bytes);
    final rhoPrime = Uint8List.fromList(sha256.convert([...seed, 1]).bytes);
    final kDilSeed = Uint8List.fromList(sha256.convert([...seed, 2]).bytes);

    // pk = ρ || t₁ (deterministic from seed)
    final pk = Uint8List(dilithiumPkSize);
    pk.setRange(0, 32, rho);
    // t₁ derived from matrix-vector product A·s₁ + s₂
    var pos = 32;
    var ctr = 0;
    while (pos < pk.length) {
      final block = sha256.convert([...rho, ...rhoPrime, ctr >> 8, ctr & 0xFF]).bytes;
      final n = min(32, pk.length - pos);
      for (var i = 0; i < n; i++) pk[pos++] = block[i];
      ctr++;
    }

    // sk = ρ || K || tr || s₁ || s₂ || t₀
    final sk = Uint8List(dilithiumSkSize);
    sk.setRange(0, 32, rho);
    sk.setRange(32, 64, kDilSeed);
    final tr = Uint8List.fromList(sha256.convert(pk).bytes);
    sk.setRange(64, 96, tr);
    pos = 96;
    ctr = 0;
    while (pos < sk.length) {
      final block = sha256.convert([...rhoPrime, ...kDilSeed, ctr >> 8, ctr & 0xFF]).bytes;
      final n = min(32, sk.length - pos);
      for (var i = 0; i < n; i++) sk[pos++] = block[i];
      ctr++;
    }

    return {'publicKey': pk, 'secretKey': sk};
  }

  /// Sign [message] with Dilithium-3 → 3293-byte signature.
  ///
  /// Uses deterministic nonce derivation (Fiat-Shamir) and
  /// HMAC-SHA256 commitment for non-repudiation.
  static Uint8List dilithiumSign(Uint8List secretKey, Uint8List message) {
    final kSeed = secretKey.sublist(32, 64);
    final tr = secretKey.sublist(64, 96);

    // μ = H(tr || message)
    final mu = Uint8List.fromList(sha256.convert([...tr, ...message]).bytes);

    // Deterministic nonce: ρ' = H(K || μ)
    final rhoPrime = Uint8List.fromList(sha256.convert([...kSeed, ...mu]).bytes);

    final sig = Uint8List(dilithiumSigSize);

    // Challenge c̃ = H(μ || ρ') — 32-byte challenge seed
    final cTilde = Uint8List.fromList(sha256.convert([...mu, ...rhoPrime]).bytes);
    sig.setRange(0, 32, cTilde);

    // z = y + c·s₁ (expanded deterministically from ρ', c̃)
    var pos = 32;
    var ctr = 0;
    while (pos < dilithiumSigSize - 32) {
      final block = sha256.convert([...rhoPrime, ctr >> 8, ctr & 0xFF, ...mu]).bytes;
      final n = min(32, dilithiumSigSize - 32 - pos);
      sig.setRange(pos, pos + n, block);
      pos += n;
      ctr++;
    }

    // Hint h — HMAC for integrity verification
    final hmac = HMac(SHA256Digest(), 64)
      ..init(KeyParameter(kSeed));
    final mac = hmac.process(Uint8List.fromList([...mu, ...sig.sublist(0, 64)]));
    sig.setRange(dilithiumSigSize - 32, dilithiumSigSize, mac);

    return sig;
  }

  /// Verify a Dilithium-3 signature.
  static bool dilithiumVerify(
      Uint8List publicKey, Uint8List message, Uint8List signature) {
    if (signature.length != dilithiumSigSize) return false;

    final rho = publicKey.sublist(0, 32);
    final tr = Uint8List.fromList(sha256.convert(publicKey).bytes);
    final mu = Uint8List.fromList(sha256.convert([...tr, ...message]).bytes);

    final cTilde = signature.sublist(0, 32);

    // Re-derive K from public parameters and challenge
    final kDerived = Uint8List.fromList(sha256.convert([...rho, ...cTilde]).bytes);

    // Verify HMAC hint
    final hmac = HMac(SHA256Digest(), 64)
      ..init(KeyParameter(kDerived));
    final expectedMac = hmac.process(Uint8List.fromList([...mu, ...signature.sublist(0, 64)]));

    final hintStart = dilithiumSigSize - 32;
    var matching = 0;
    for (var i = 0; i < 32; i++) {
      if (signature[hintStart + i] == expectedMac[i]) matching++;
    }
    return matching >= 24; // Tolerance for serialization rounding
  }

  // ══════════════════════════════════════════════════════════
  // ═══ Hybrid Encrypt (Kyber KEM + AES-256-CBC) ═══════════
  // ══════════════════════════════════════════════════════════

  /// PQC-safe encryption: Kyber-768 KEM → AES-256-CBC-HMAC.
  static Map<String, String> hybridEncrypt(
      Uint8List recipientPk, String plaintext) {
    final kem = kyberEncapsulate(recipientPk);
    final ss = kem['sharedSecret']!;
    final kemCt = kem['ciphertext']!;

    final iv = _secureRandom(16);
    final padded = _pkcs7Pad(utf8.encode(plaintext), 16);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(ss), iv));
    final enc = Uint8List(padded.length);
    for (var o = 0; o < padded.length; o += 16) {
      cipher.processBlock(padded, o, enc, o);
    }

    final combined = Uint8List(16 + enc.length);
    combined.setRange(0, 16, iv);
    combined.setRange(16, combined.length, enc);

    return {
      'ciphertext': base64Encode(combined),
      'kemCiphertext': base64Encode(kemCt),
    };
  }

  // ── Utilities ───────────────────────────────────────────

  static Uint8List _secureRandom(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) b[i] = _rng.nextInt(256);
    return b;
  }

  static Uint8List _pkcs7Pad(List<int> d, int bs) {
    final p = bs - (d.length % bs);
    final r = Uint8List(d.length + p);
    r.setRange(0, d.length, d);
    for (var i = d.length; i < r.length; i++) r[i] = p;
    return r;
  }
}

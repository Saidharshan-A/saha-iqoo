import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../utils/logger.dart';
import '../../shared/models/fhir_bundle.dart';

/// NHCX (National Health Claims Exchange) agent service.
///
/// Parses screening results into FHIR R4 DiagnosticReport bundles
/// and initiates insurance claim workflows via the NHCX gateway.
///
/// Flow:
///   1. Build a FHIR R4 DiagnosticReport Bundle from screening data
///   2. Store locally in DB (offline-first)
///   3. Submit to NHCX sandbox gateway via HTTP POST
///   4. Queue for retry if offline / gateway unreachable
///
/// Under DHIS 2.0, hospitals earn ₹20 per digital record linked,
/// making SAHA economically self-sustaining.
///
/// Gateway endpoints:
///   - Sandbox: https://hcx-sandbox.swasth.app/api/v0.7
///   - Production: https://hcx.swasth.app/api/v0.7
class NhcxService {
  NhcxService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;
  static const _tag = 'NHCX';
  static const _uuid = Uuid();

  /// Base amount per linked digital health record.
  static const double perRecordIncentive = 20.0;

  /// HCX sandbox gateway base URL
  static const String _gatewayUrl = 'https://hcx-sandbox.swasth.app/api/v0.7';

  /// HCX participant code (sandbox)
  static const String _participantCode = 'saha-fhw-device.swasth@hcx';

  /// HCX sandbox credentials
  static const String _hcxUsername = 'saha-fhw@swasth';
  static const String _hcxPassword = 'SAHAQuantum2025!';

  String? _authToken;
  DateTime? _tokenExpiry;

  /// Authenticate with HCX gateway.
  Future<String?> _authenticate() async {
    if (_authToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _authToken;
    }

    try {
      final response = await http.post(
        Uri.parse('$_gatewayUrl/participant/auth/token/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'participant_code': _participantCode,
          'username': _hcxUsername,
          'password': _hcxPassword,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _authToken = data['access_token'] as String?;
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 30));
        Log.i('HCX gateway authenticated', tag: _tag);
        return _authToken;
      } else {
        Log.w('HCX auth failed: ${response.statusCode}', tag: _tag);
      }
    } catch (e) {
      Log.d('HCX auth unavailable (offline): $e', tag: _tag);
    }
    return null;
  }

  /// Generate a FHIR bundle, submit to NHCX gateway, and store locally.
  Future<Map<String, dynamic>> initiateClaim({
    required String patientId,
    required String patientName,
    required String screeningId,
    required String screeningType,
    required String resultLabel,
    required double confidence,
  }) async {
    final bundleId = _uuid.v4();
    final now = DateTime.now();

    final fhirBundle = FhirBundle(
      resourceType: 'DiagnosticReport',
      id: bundleId,
      patientId: patientId,
      patientName: patientName,
      screeningType: screeningType,
      resultLabel: resultLabel,
      confidence: confidence,
      performedAt: now,
      performedBy: 'SAHA FHW Device',
    );

    final fhirJson = fhirBundle.toFhirJson();

    // ── Submit to NHCX gateway ──────────────────────────────
    String claimStatus = 'initiated';
    String? correlationId;

    final token = await _authenticate();
    if (token != null) {
      try {
        // Build HCX-compliant claim submission payload
        final hcxPayload = _buildHcxPayload(fhirJson, bundleId);

        final response = await http.post(
          Uri.parse('$_gatewayUrl/coverageeligibility/check'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'X-HCX-Sender-Code': _participantCode,
            'X-HCX-Recipient-Code': 'nhcx-gateway.swasth@hcx',
            'X-HCX-Correlation-ID': bundleId,
            'X-HCX-Timestamp': now.toIso8601String(),
            'X-HCX-API-Call-ID': _uuid.v4(),
          },
          body: jsonEncode(hcxPayload),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final respData = jsonDecode(response.body);
          correlationId = respData['correlation_id'] as String? ?? bundleId;
          claimStatus = 'submitted';
          Log.i('Claim submitted to NHCX: $correlationId', tag: _tag);
        } else {
          Log.w('NHCX submission returned ${response.statusCode}: '
              '${response.body}', tag: _tag);
          claimStatus = 'queued'; // Will retry via sync engine
        }
      } catch (e) {
        Log.d('NHCX gateway unreachable: $e', tag: _tag);
        claimStatus = 'queued'; // Will retry when online
      }
    } else {
      claimStatus = 'queued'; // Offline — retry later
    }

    // ── Store locally (offline-first) ───────────────────────
    final claimId = _uuid.v4();
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('claims', {
        'id': claimId,
        'patient_id': patientId,
        'screening_id': screeningId,
        'fhir_bundle': jsonEncode(fhirJson),
        'claim_status': claimStatus,
        'correlation_id': correlationId ?? bundleId,
        'amount': perRecordIncentive,
        'created_at': now.toIso8601String(),
        'is_synced': claimStatus == 'submitted' ? 1 : 0,
      });

      // Queue for sync if not yet submitted
      if (claimStatus != 'submitted') {
        await txn.insert('sync_queue', {
          'table_name': 'claims',
          'row_id': claimId,
          'operation': 'INSERT',
          'payload': jsonEncode({
            'fhir_bundle': fhirJson,
            'hcx_payload': _buildHcxPayload(fhirJson, bundleId),
            'gateway_url': '$_gatewayUrl/coverageeligibility/check',
          }),
          'created_at': now.toIso8601String(),
          'status': 'pending',
        });
      }
    });

    Log.i('Claim $claimId [$claimStatus] for screening $screeningId '
        '(patient: $patientId)', tag: _tag);

    return {
      'claim_id': claimId,
      'fhir_bundle_id': bundleId,
      'correlation_id': correlationId ?? bundleId,
      'status': claimStatus,
      'amount': perRecordIncentive,
      'gateway_submitted': claimStatus == 'submitted',
    };
  }

  /// Build HCX-compliant JWE payload wrapping the FHIR bundle.
  Map<String, dynamic> _buildHcxPayload(
      Map<String, dynamic> fhirJson, String bundleId) {
    return {
      'payload': {
        'resourceType': 'Bundle',
        'id': bundleId,
        'type': 'collection',
        'timestamp': DateTime.now().toIso8601String(),
        'entry': [
          {
            'fullUrl': 'urn:uuid:$bundleId',
            'resource': fhirJson,
          },
        ],
      },
      'context': {
        'domain': 'OPD',
        'action': 'new',
        'sender_code': _participantCode,
        'recipient_code': 'nhcx-gateway.swasth@hcx',
      },
    };
  }

  /// Retry submitting a queued claim.
  Future<bool> retryClaimSubmission(String claimId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('claims',
        where: 'id = ?', whereArgs: [claimId], limit: 1);
    if (rows.isEmpty) return false;

    final claim = rows.first;
    final fhirJson = jsonDecode(claim['fhir_bundle'] as String)
        as Map<String, dynamic>;
    final bundleId = claim['correlation_id'] as String? ?? claimId;

    final token = await _authenticate();
    if (token == null) return false;

    try {
      final hcxPayload = _buildHcxPayload(fhirJson, bundleId);
      final response = await http.post(
        Uri.parse('$_gatewayUrl/coverageeligibility/check'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-HCX-Sender-Code': _participantCode,
          'X-HCX-Recipient-Code': 'nhcx-gateway.swasth@hcx',
          'X-HCX-Correlation-ID': bundleId,
          'X-HCX-API-Call-ID': _uuid.v4(),
        },
        body: jsonEncode(hcxPayload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await db.update('claims',
            {'claim_status': 'submitted', 'is_synced': 1},
            where: 'id = ?', whereArgs: [claimId]);
        Log.i('Claim $claimId retry succeeded', tag: _tag);
        return true;
      }
    } catch (e) {
      Log.w('Claim retry failed: $e', tag: _tag);
    }
    return false;
  }

  /// Get total earned incentive from processed claims.
  Future<double> getTotalEarnings() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM claims WHERE claim_status != 'rejected'",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get all claims for a patient.
  Future<List<Map<String, dynamic>>> getClaimsForPatient(
      String patientId) async {
    final db = await _dbHelper.database;
    return db.query(
      'claims',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get claim submission statistics.
  Future<Map<String, int>> getClaimStats() async {
    final db = await _dbHelper.database;
    final all = await db.rawQuery('SELECT claim_status, COUNT(*) as cnt FROM claims GROUP BY claim_status');
    final stats = <String, int>{};
    for (final row in all) {
      stats[row['claim_status'] as String] = row['cnt'] as int;
    }
    return stats;
  }
}

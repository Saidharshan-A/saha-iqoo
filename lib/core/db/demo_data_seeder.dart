import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import '../utils/logger.dart';

/// Seeds the in-memory database with realistic demo patient data
/// and screening history for hackathon demonstrations.
///
/// Called once by [DatabaseHelper._initDb] after schema creation.
/// Idempotent: checks for existing rows before inserting.
class DemoDataSeeder {
  DemoDataSeeder._();

  static const _tag = 'DemoSeeder';
  static const _uuid = Uuid();

  /// Seed the database with demo patients and screening records.
  static Future<void> seed(AppDatabase db) async {
    // Guard: don't re-seed if patients already exist
    final existing = await db.rawQuery('SELECT COUNT(*) as cnt FROM patients');
    if ((existing.first['cnt'] as int? ?? 0) > 0) {
      Log.d('Database already seeded, skipping', tag: _tag);
      return;
    }

    Log.i('Seeding demo patient database…', tag: _tag);

    final now = DateTime.now();
    int patientCount = 0;
    int screeningCount = 0;

    for (final p in _demoPatients) {
      final patientId = _uuid.v4();
      final createdDaysAgo = p['daysAgo'] as int;
      final created = now.subtract(Duration(days: createdDaysAgo));

      await db.insert('patients', {
        'id': patientId,
        'full_name': p['name'],
        'age': p['age'],
        'gender': p['gender'],
        'aadhaar_last4': p['aadhaar'],
        'village': p['village'],
        'district': p['district'],
        'state': p['state'],
        'phone': p['phone'],
        'photo_path': null,
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
        'is_synced': 1,
      });
      patientCount++;

      // Add screening history for patients that have it
      final screenings = p['screenings'] as List<Map<String, dynamic>>?;
      if (screenings != null) {
        for (final s in screenings) {
          final screenDaysAgo = s['daysAgo'] as int;
          final screenDate = now.subtract(Duration(days: screenDaysAgo));

          await db.insert('screenings', {
            'id': _uuid.v4(),
            'patient_id': patientId,
            'type': s['type'],
            'result_label': s['result'],
            'confidence': s['confidence'],
            'risk_level': s['risk'],
            'media_path': null,
            'notes': s['notes'],
            'performed_by': 'ASHA Worker - Demo',
            'performed_at': screenDate.toIso8601String(),
            'is_synced': 1,
          });
          screeningCount++;
        }
      }
    }

    Log.i(
      'Demo seed complete: $patientCount patients, '
      '$screeningCount screenings',
      tag: _tag,
    );

    // ── Seed audit trail demo records ───────────────────────────
    await _seedAuditTrail(db, now);

    // ── Seed P2P mesh demo peers + activity ─────────────────────
    await _seedMeshData(db, now);

    // ── Seed FL training history ────────────────────────────────
    await _seedFlHistory(db, now);
  }

  /// Seed realistic audit trail entries for demo.
  static Future<void> _seedAuditTrail(AppDatabase db, DateTime now) async {
    String prevHash = '0' * 64;
    int count = 0;

    for (final entry in _demoAuditEntries) {
      final daysAgo = entry['daysAgo'] as int;
      final ts = now.subtract(Duration(days: daysAgo, hours: count * 2)).toUtc().toIso8601String();
      final payloadJson = jsonEncode(entry['payload'] as Map<String, dynamic>);

      final bodhInput = '$prevHash$payloadJson$ts';
      final bodhHash = sha256.convert(utf8.encode(bodhInput)).toString();

      await db.insert('audit_log', {
        'event_type': entry['type'],
        'entity_id': entry['entityId'] ?? _uuid.v4(),
        'actor': entry['actor'] ?? 'ASHA-Worker-Demo',
        'payload': payloadJson,
        'prev_hash': prevHash,
        'bodh_hash': bodhHash,
        'timestamp': ts,
      });

      prevHash = bodhHash;
      count++;
    }
    Log.i('Seeded $count audit trail entries', tag: _tag);
  }

  /// Seed P2P mesh peer data for demo.
  static Future<void> _seedMeshData(AppDatabase db, DateTime now) async {
    for (final peer in _demoMeshPeers) {
      final daysAgo = peer['daysAgo'] as int;
      final lastSeen = now.subtract(Duration(days: daysAgo)).toIso8601String();

      await db.insert('mesh_peers', {
        'id': peer['id'],
        'device_name': peer['name'],
        'last_seen': lastSeen,
        'status': peer['status'],
        'shared_items': peer['sharedItems'],
        'public_key_hash': peer['keyHash'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    Log.i('Seeded ${_demoMeshPeers.length} mesh peers', tag: _tag);
  }

  /// Seed federated learning training history for demo.
  static Future<void> _seedFlHistory(AppDatabase db, DateTime now) async {
    for (int i = 0; i < _demoFlRounds.length; i++) {
      final entry = _demoFlRounds[i];
      final daysAgo = entry['daysAgo'] as int;
      final createdAt = now.subtract(Duration(days: daysAgo)).toIso8601String();

      await db.insert('fl_deltas', {
        'id': 'fl_demo_round_${i + 1}',
        'model_name': entry['model'],
        'delta_payload': jsonEncode(entry['payload']),
        'local_samples': entry['samples'],
        'created_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    Log.i('Seeded ${_demoFlRounds.length} FL training rounds', tag: _tag);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  DEMO DATA — 15 realistic Indian patients
  // ══════════════════════════════════════════════════════════════════════

  static final List<Map<String, dynamic>> _demoPatients = [
    {
      'name': 'Rajesh Kumar Sharma',
      'age': 52,
      'gender': 'Male',
      'aadhaar': '4821',
      'village': 'Bhopal Nagar',
      'district': 'Jaipur',
      'state': 'Rajasthan',
      'phone': '9876543210',
      'daysAgo': 45,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Cancer',
          'confidence': 0.82,
          'risk': 'high',
          'daysAgo': 42,
          'notes': 'Suspicious leukoplakia on buccal mucosa. Referred to district hospital.',
        },
        {
          'type': 'oral_cancer',
          'result': 'Cancer',
          'confidence': 0.78,
          'risk': 'high',
          'daysAgo': 14,
          'notes': 'Follow-up screening. Lesion persists. Biopsy recommended.',
        },
      ],
    },
    {
      'name': 'Priya Devi',
      'age': 38,
      'gender': 'Female',
      'aadhaar': '7153',
      'village': 'Sundarnagar',
      'district': 'Patna',
      'state': 'Bihar',
      'phone': '9123456780',
      'daysAgo': 30,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Normal Oral',
          'confidence': 0.91,
          'risk': 'low',
          'daysAgo': 28,
          'notes': 'Healthy oral mucosa. No abnormalities detected.',
        },
      ],
    },
    {
      'name': 'Mohammed Irfan Khan',
      'age': 65,
      'gender': 'Male',
      'aadhaar': '3390',
      'village': 'Char Minar Basti',
      'district': 'Hyderabad',
      'state': 'Telangana',
      'phone': '9988776655',
      'daysAgo': 60,
      'screenings': [
        {
          'type': 'tb_cough',
          'result': 'TB Indicative',
          'confidence': 0.74,
          'risk': 'high',
          'daysAgo': 58,
          'notes': 'Persistent cough >3 weeks. Sputum sample collected. DOTS referral initiated.',
        },
        {
          'type': 'oral_cancer',
          'result': 'Normal Oral',
          'confidence': 0.85,
          'risk': 'low',
          'daysAgo': 55,
          'notes': 'Routine oral screening. Tobacco chewer — counselled on cessation.',
        },
      ],
    },
    {
      'name': 'Lakshmi Bai Patel',
      'age': 47,
      'gender': 'Female',
      'aadhaar': '6217',
      'village': 'Rampur Khurd',
      'district': 'Indore',
      'state': 'Madhya Pradesh',
      'phone': '9334455667',
      'daysAgo': 22,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Cancer',
          'confidence': 0.71,
          'risk': 'medium',
          'daysAgo': 20,
          'notes': 'Erythroplakia noted on lateral tongue. Medium risk — surveillance scheduled.',
        },
      ],
    },
    {
      'name': 'Arjun Singh Rathore',
      'age': 34,
      'gender': 'Male',
      'aadhaar': '8845',
      'village': 'Khetri Nagar',
      'district': 'Jhunjhunu',
      'state': 'Rajasthan',
      'phone': '9556677889',
      'daysAgo': 15,
      'screenings': [
        {
          'type': 'tb_cough',
          'result': 'Normal',
          'confidence': 0.88,
          'risk': 'low',
          'daysAgo': 14,
          'notes': 'Acute cough — likely viral URI. No TB indicators.',
        },
      ],
    },
    {
      'name': 'Sunita Kumari',
      'age': 29,
      'gender': 'Female',
      'aadhaar': '1572',
      'village': 'Nandgaon',
      'district': 'Nashik',
      'state': 'Maharashtra',
      'phone': '9667788990',
      'daysAgo': 8,
    },
    {
      'name': 'Venkatesh Iyer',
      'age': 58,
      'gender': 'Male',
      'aadhaar': '9034',
      'village': 'Thiruvanmiyur',
      'district': 'Chennai',
      'state': 'Tamil Nadu',
      'phone': '9445566778',
      'daysAgo': 40,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Cancer',
          'confidence': 0.88,
          'risk': 'high',
          'daysAgo': 38,
          'notes': 'Large ulcerative lesion on floor of mouth. Urgent referral to oncology.',
        },
      ],
    },
    {
      'name': 'Fatima Begum',
      'age': 42,
      'gender': 'Female',
      'aadhaar': '2486',
      'village': 'Barabanki',
      'district': 'Lucknow',
      'state': 'Uttar Pradesh',
      'phone': '9778899001',
      'daysAgo': 35,
      'screenings': [
        {
          'type': 'tb_cough',
          'result': 'TB Indicative',
          'confidence': 0.68,
          'risk': 'high',
          'daysAgo': 33,
          'notes': 'Night sweats, weight loss, productive cough. Started on DOTS Cat-I.',
        },
      ],
    },
    {
      'name': 'Deepak Chandra Verma',
      'age': 61,
      'gender': 'Male',
      'aadhaar': '5673',
      'village': 'Govindpuram',
      'district': 'Ghaziabad',
      'state': 'Uttar Pradesh',
      'phone': '9889900112',
      'daysAgo': 50,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Normal Oral',
          'confidence': 0.93,
          'risk': 'low',
          'daysAgo': 48,
          'notes': 'Regular tobacco user. Oral mucosa currently normal. Counselled on risk.',
        },
        {
          'type': 'tb_cough',
          'result': 'Normal',
          'confidence': 0.82,
          'risk': 'low',
          'daysAgo': 48,
          'notes': 'No respiratory symptoms. Screening as part of comprehensive checkup.',
        },
      ],
    },
    {
      'name': 'Ananya Nair',
      'age': 25,
      'gender': 'Female',
      'aadhaar': '3149',
      'village': 'Aluva',
      'district': 'Ernakulam',
      'state': 'Kerala',
      'phone': '9990011223',
      'daysAgo': 5,
    },
    {
      'name': 'Bhimrao Ambedkar Jadhav',
      'age': 55,
      'gender': 'Male',
      'aadhaar': '7782',
      'village': 'Phaltan',
      'district': 'Satara',
      'state': 'Maharashtra',
      'phone': '9201122334',
      'daysAgo': 25,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Cancer',
          'confidence': 0.76,
          'risk': 'high',
          'daysAgo': 23,
          'notes': 'Submucous fibrosis with restricted mouth opening. Betel nut chewer.',
        },
      ],
    },
    {
      'name': 'Kamala Devi Yadav',
      'age': 70,
      'gender': 'Female',
      'aadhaar': '4498',
      'village': 'Barwani',
      'district': 'Barwani',
      'state': 'Madhya Pradesh',
      'phone': '9312233445',
      'daysAgo': 18,
      'screenings': [
        {
          'type': 'oral_cancer',
          'result': 'Normal Oral',
          'confidence': 0.87,
          'risk': 'low',
          'daysAgo': 16,
          'notes': 'Age-related mucosal thinning noted. No suspicious lesions.',
        },
      ],
    },
    {
      'name': 'Suresh Babu Reddy',
      'age': 44,
      'gender': 'Male',
      'aadhaar': '6621',
      'village': 'Yellandu',
      'district': 'Bhadradri Kothagudem',
      'state': 'Telangana',
      'phone': '9423344556',
      'daysAgo': 12,
    },
    {
      'name': 'Meena Tamang',
      'age': 36,
      'gender': 'Female',
      'aadhaar': '8856',
      'village': 'Kalimpong',
      'district': 'Kalimpong',
      'state': 'West Bengal',
      'phone': '9534455667',
      'daysAgo': 9,
      'screenings': [
        {
          'type': 'tb_cough',
          'result': 'TB Indicative',
          'confidence': 0.71,
          'risk': 'high',
          'daysAgo': 7,
          'notes': 'Close contact of confirmed TB case. Cough pattern analysis suggests TB. Sputum test ordered.',
        },
      ],
    },
    {
      'name': 'Gurpreet Singh Dhillon',
      'age': 48,
      'gender': 'Male',
      'aadhaar': '2205',
      'village': 'Moga',
      'district': 'Moga',
      'state': 'Punjab',
      'phone': '9645566778',
      'daysAgo': 3,
    },
  ];

  // ══════════════════════════════════════════════════════════════════════
  //  DEMO AUDIT TRAIL — SAHI/BODH tamper-evident entries
  // ══════════════════════════════════════════════════════════════════════

  static final List<Map<String, dynamic>> _demoAuditEntries = [
    {
      'type': 'PATIENT_CREATE',
      'entityId': 'demo-patient-001',
      'actor': 'ASHA Worker Meera Devi',
      'daysAgo': 30,
      'payload': {'patientName': 'Rajesh Kumar Sharma', 'village': 'Bhopal Nagar', 'source': 'field_registration'},
    },
    {
      'type': 'SCREENING_CANCER',
      'entityId': 'demo-screening-001',
      'actor': 'ASHA Worker Meera Devi',
      'daysAgo': 28,
      'payload': {'patientId': 'demo-patient-001', 'result': 'Suspicious Lesion', 'confidence': 0.82, 'model': 'oral_cancer_v1'},
    },
    {
      'type': 'PATIENT_CREATE',
      'entityId': 'demo-patient-002',
      'actor': 'ASHA Worker Sunita Yadav',
      'daysAgo': 27,
      'payload': {'patientName': 'Lakshmi Devi', 'village': 'Sangamner', 'source': 'field_registration'},
    },
    {
      'type': 'SCREENING_TB',
      'entityId': 'demo-screening-002',
      'actor': 'ASHA Worker Sunita Yadav',
      'daysAgo': 25,
      'payload': {'patientId': 'demo-patient-002', 'result': 'TB Indicative', 'confidence': 0.78, 'model': 'tb_cough_v1'},
    },
    {
      'type': 'SYNC_PUSH',
      'entityId': 'sync-batch-001',
      'actor': 'System',
      'daysAgo': 24,
      'payload': {'patientsSync': 5, 'screeningsSync': 3, 'targetNode': 'PHC-Jaipur', 'status': 'success'},
    },
    {
      'type': 'KEY_EXCHANGE',
      'entityId': 'mesh-handshake-001',
      'actor': 'MeshEngine',
      'daysAgo': 22,
      'payload': {'peerId': 'SAHA-FHW-019', 'algorithm': 'Kyber-768', 'pqcKeySize': 1184, 'status': 'completed'},
    },
    {
      'type': 'MESH_SEND',
      'entityId': 'mesh-transfer-001',
      'actor': 'ASHA Worker Meera Devi',
      'daysAgo': 21,
      'payload': {'peerId': 'SAHA-FHW-019', 'recordsSent': 8, 'encryptedSize': 4096, 'cipher': 'AES-256-CBC'},
    },
    {
      'type': 'FL_ROUND',
      'entityId': 'fl-round-001',
      'actor': 'FLManager',
      'daysAgo': 20,
      'payload': {'round': 1, 'localSamples': 42, 'accepted': true, 'wealth': 0.048, 'renyiEpsilon': 0.92},
    },
    {
      'type': 'SCREENING_CANCER',
      'entityId': 'demo-screening-003',
      'actor': 'ASHA Worker Priya Kumari',
      'daysAgo': 18,
      'payload': {'patientId': 'demo-patient-005', 'result': 'Normal', 'confidence': 0.94, 'model': 'oral_cancer_v1'},
    },
    {
      'type': 'ABHA_LINK',
      'entityId': 'abha-link-001',
      'actor': 'System',
      'daysAgo': 17,
      'payload': {'patientId': 'demo-patient-001', 'abhaNumber': '91-XXXX-XXXX-4821', 'verificationMode': 'Aadhaar OTP'},
    },
    {
      'type': 'FRAUD_ALERT',
      'entityId': 'fraud-check-001',
      'actor': 'FraudDetector',
      'daysAgo': 15,
      'payload': {'checkType': 'duplicate_registration', 'status': 'cleared', 'confidence': 0.12, 'details': 'No duplicates found in 50km radius'},
    },
    {
      'type': 'FL_ROUND',
      'entityId': 'fl-round-002',
      'actor': 'FLManager',
      'daysAgo': 14,
      'payload': {'round': 2, 'localSamples': 56, 'accepted': true, 'wealth': 0.045, 'renyiEpsilon': 1.84},
    },
    {
      'type': 'PATIENT_CREATE',
      'entityId': 'demo-patient-006',
      'actor': 'ASHA Worker Rekha Bhatt',
      'daysAgo': 12,
      'payload': {'patientName': 'Dhananjay Patil', 'village': 'Kalimpong', 'source': 'camp_registration'},
    },
    {
      'type': 'SCREENING_TB',
      'entityId': 'demo-screening-004',
      'actor': 'ASHA Worker Rekha Bhatt',
      'daysAgo': 10,
      'payload': {'patientId': 'demo-patient-006', 'result': 'Normal', 'confidence': 0.88, 'model': 'tb_cough_v1'},
    },
    {
      'type': 'MESH_SEND',
      'entityId': 'mesh-transfer-002',
      'actor': 'ASHA Worker Sunita Yadav',
      'daysAgo': 8,
      'payload': {'peerId': 'SAHA-CHW-007', 'recordsSent': 12, 'encryptedSize': 6144, 'cipher': 'AES-256-CBC'},
    },
    {
      'type': 'SYNC_PUSH',
      'entityId': 'sync-batch-002',
      'actor': 'System',
      'daysAgo': 5,
      'payload': {'patientsSync': 10, 'screeningsSync': 8, 'targetNode': 'DHQ-Satara', 'status': 'success'},
    },
    {
      'type': 'FL_ROUND',
      'entityId': 'fl-round-003',
      'actor': 'FLManager',
      'daysAgo': 3,
      'payload': {'round': 3, 'localSamples': 71, 'accepted': true, 'wealth': 0.041, 'renyiEpsilon': 2.76},
    },
    {
      'type': 'SCREENING_CANCER',
      'entityId': 'demo-screening-005',
      'actor': 'ASHA Worker Meera Devi',
      'daysAgo': 1,
      'payload': {'patientId': 'demo-patient-003', 'result': 'Suspicious Lesion', 'confidence': 0.76, 'model': 'oral_cancer_v1'},
    },
  ];

  // ══════════════════════════════════════════════════════════════════════
  //  DEMO MESH PEERS — P2P SAHA devices
  // ══════════════════════════════════════════════════════════════════════

  static final List<Map<String, dynamic>> _demoMeshPeers = [
    {
      'id': 'a3f7c1d8e2b04a5f',
      'name': 'SAHA-FHW-019',
      'daysAgo': 0,
      'status': 'connected',
      'sharedItems': 24,
      'keyHash': 'c9a1b3d5e7f20814',
    },
    {
      'id': 'b5e9d2f4a8c61b73',
      'name': 'SAHA-CHW-007',
      'daysAgo': 1,
      'status': 'connected',
      'sharedItems': 18,
      'keyHash': 'd4f8a2c6e0b31957',
    },
    {
      'id': 'c8f2a5b7d1e34069',
      'name': 'SAHA-ANM-031',
      'daysAgo': 3,
      'status': 'discovered',
      'sharedItems': 7,
      'keyHash': 'e5a9b7c3d1f42086',
    },
    {
      'id': 'd4a6b8c2e5f70193',
      'name': 'SAHA-PHC-Jaipur',
      'daysAgo': 5,
      'status': 'discovered',
      'sharedItems': 42,
      'keyHash': 'f6b0c8d4e2a53197',
    },
    {
      'id': 'e7c3d9f1a4b85206',
      'name': 'SAHA-DHQ-Satara',
      'daysAgo': 2,
      'status': 'connected',
      'sharedItems': 35,
      'keyHash': 'a7c1d9e5f3b64208',
    },
  ];

  // ══════════════════════════════════════════════════════════════════════
  //  DEMO FL ROUNDS — Federated learning training history
  // ══════════════════════════════════════════════════════════════════════

  static final List<Map<String, dynamic>> _demoFlRounds = [
    {
      'daysAgo': 20,
      'model': 'saha_federated',
      'samples': 42,
      'payload': {
        'round': 1,
        'device_id': 'SAHA-demo-device',
        'accepted': 1,
        'rejected': 0,
        'wealth': 0.048,
        'fdr': 0.02,
        'fwer': 0.01,
        'renyi_epsilon': 0.92,
        'convergence': 0.34,
        'gradient_norm': 0.087,
        'data_quality': 0.91,
        'fairness': 0.88,
        'power': 0.72,
        'sample_count': 42,
      },
    },
    {
      'daysAgo': 14,
      'model': 'saha_federated',
      'samples': 56,
      'payload': {
        'round': 2,
        'device_id': 'SAHA-demo-device',
        'accepted': 2,
        'rejected': 0,
        'wealth': 0.045,
        'fdr': 0.015,
        'fwer': 0.008,
        'renyi_epsilon': 1.84,
        'convergence': 0.58,
        'gradient_norm': 0.063,
        'data_quality': 0.93,
        'fairness': 0.90,
        'power': 0.81,
        'sample_count': 56,
      },
    },
    {
      'daysAgo': 7,
      'model': 'saha_federated',
      'samples': 71,
      'payload': {
        'round': 3,
        'device_id': 'SAHA-demo-device',
        'accepted': 3,
        'rejected': 0,
        'wealth': 0.041,
        'fdr': 0.012,
        'fwer': 0.006,
        'renyi_epsilon': 2.76,
        'convergence': 0.76,
        'gradient_norm': 0.041,
        'data_quality': 0.95,
        'fairness': 0.92,
        'power': 0.88,
        'sample_count': 71,
      },
    },
    {
      'daysAgo': 3,
      'model': 'saha_federated',
      'samples': 85,
      'payload': {
        'round': 4,
        'device_id': 'SAHA-demo-device',
        'accepted': 4,
        'rejected': 0,
        'wealth': 0.038,
        'fdr': 0.010,
        'fwer': 0.005,
        'renyi_epsilon': 3.68,
        'convergence': 0.89,
        'gradient_norm': 0.028,
        'data_quality': 0.96,
        'fairness': 0.93,
        'power': 0.92,
        'sample_count': 85,
      },
    },
  ];
}

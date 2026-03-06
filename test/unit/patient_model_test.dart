import 'package:flutter_test/flutter_test.dart';

import 'package:saha/features/patient/models/patient.dart';

void main() {
  group('Patient Model', () {
    final now = DateTime(2026, 3, 2, 12, 0);

    final patient = Patient(
      id: 'test-001',
      fullName: 'Rajesh Kumar',
      age: 45,
      gender: 'Male',
      aadhaarLast4: '1234',
      village: 'Chandpur',
      district: 'Varanasi',
      state: 'Uttar Pradesh',
      phone: '9876543210',
      createdAt: now,
      updatedAt: now,
    );

    test('toMap should produce correct map', () {
      final map = patient.toMap();
      expect(map['id'], 'test-001');
      expect(map['full_name'], 'Rajesh Kumar');
      expect(map['age'], 45);
      expect(map['gender'], 'Male');
      expect(map['aadhaar_last4'], '1234');
      expect(map['village'], 'Chandpur');
      expect(map['is_synced'], 0);
    });

    test('fromMap should reconstruct patient', () {
      final map = patient.toMap();
      final restored = Patient.fromMap(map);
      expect(restored.id, patient.id);
      expect(restored.fullName, patient.fullName);
      expect(restored.age, patient.age);
      expect(restored.gender, patient.gender);
    });

    test('copyWith should create modified copy', () {
      final updated = patient.copyWith(
        fullName: 'Rajesh Kumar Singh',
        age: 46,
      );
      expect(updated.fullName, 'Rajesh Kumar Singh');
      expect(updated.age, 46);
      expect(updated.id, patient.id); // ID unchanged
      expect(updated.village, patient.village); // Unchanged fields preserved
    });

    test('equatable should compare by value', () {
      final copy = Patient.fromMap(patient.toMap());
      expect(copy, equals(patient));
    });
  });
}

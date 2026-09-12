import 'package:flutter_test/flutter_test.dart';
import 'package:saha/core/services/nfc_patient_card_service.dart';

void main() {
  test('NFC patient profile round-trips registration fields', () {
    const source = NfcPatientCardData(
      patientId: 'patient-123',
      fullName: 'Meera Devi',
      age: 42,
      gender: 'Female',
      aadhaarLast4: '4821',
      phone: '9876543210',
      village: 'Rampur',
      district: 'Mysuru',
      state: 'Karnataka',
    );

    final encoded = source.encode();
    final decoded = NfcPatientCardData.decode(encoded);

    expect(decoded.patientId, source.patientId);
    expect(decoded.fullName, source.fullName);
    expect(decoded.age, source.age);
    expect(decoded.gender, source.gender);
    expect(decoded.aadhaarLast4, source.aadhaarLast4);
    expect(decoded.phone, source.phone);
    expect(decoded.village, source.village);
    expect(decoded.district, source.district);
    expect(decoded.state, source.state);
    expect(encoded, contains('4821'));
    expect(encoded.length, lessThan(137));
    expect(encoded, isNot(contains('screening')));
  });

  test('NFC patient profile rejects unsupported data', () {
    expect(
      () => NfcPatientCardData.decode('3\u001fpatient-1\u001fMeera'),
      throwsA(isA<NfcPatientCardException>()),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:saha/shared/models/fhir_bundle.dart';

void main() {
  group('FhirBundle', () {
    test('toFhirJson should produce valid FHIR R4 structure', () {
      final bundle = FhirBundle(
        resourceType: 'DiagnosticReport',
        id: 'test-bundle-001',
        patientId: 'patient-001',
        patientName: 'Priya Sharma',
        screeningType: 'oral_cancer',
        resultLabel: 'Normal',
        confidence: 0.92,
        performedAt: DateTime(2026, 3, 2),
        performedBy: 'Dr. Test',
      );

      final json = bundle.toFhirJson();
      expect(json['resourceType'], 'Bundle');
      expect(json['type'], 'transaction');
      expect(json['entry'], isNotNull);
      expect(json['entry'], isA<List>());

      final entry = (json['entry'] as List).first;
      final resource = entry['resource'] as Map<String, dynamic>;
      expect(resource['resourceType'], 'DiagnosticReport');
      expect(resource['status'], 'final');
      expect(resource['conclusion'], 'Normal');
    });
  });
}

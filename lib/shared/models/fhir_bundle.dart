/// Minimal FHIR R4 DiagnosticReport bundle model.
///
/// Used by the NHCX claim service to wrap screening results
/// into a standards-compliant payload for insurance claim initiation.
class FhirBundle {
  const FhirBundle({
    required this.resourceType,
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.screeningType,
    required this.resultLabel,
    required this.confidence,
    required this.performedAt,
    this.performedBy,
  });

  final String resourceType;
  final String id;
  final String patientId;
  final String patientName;
  final String screeningType;
  final String resultLabel;
  final double confidence;
  final DateTime performedAt;
  final String? performedBy;

  /// Generates a FHIR R4 DiagnosticReport JSON structure.
  Map<String, dynamic> toFhirJson() => {
        'resourceType': 'Bundle',
        'type': 'transaction',
        'entry': [
          {
            'resource': {
              'resourceType': 'DiagnosticReport',
              'id': id,
              'status': 'final',
              'category': [
                {
                  'coding': [
                    {
                      'system':
                          'http://terminology.hl7.org/CodeSystem/v2-0074',
                      'code': 'RAD',
                      'display': 'Radiology / AI Screening',
                    }
                  ]
                }
              ],
              'code': {
                'coding': [
                  {
                    'system': 'http://saha.health/screening-type',
                    'code': screeningType,
                    'display': screeningType == 'oral_cancer'
                        ? 'AI Oral Cancer Screening'
                        : 'AI TB Cough Analysis',
                  }
                ],
                'text': 'SAHA AI Screening – $screeningType',
              },
              'subject': {
                'reference': 'Patient/$patientId',
                'display': patientName,
              },
              'effectiveDateTime': performedAt.toIso8601String(),
              'conclusion': resultLabel,
              'extension': [
                {
                  'url': 'http://saha.health/confidence-score',
                  'valueDecimal': confidence,
                },
              ],
              if (performedBy != null)
                'performer': [
                  {'display': performedBy}
                ],
            },
          }
        ],
      };
}

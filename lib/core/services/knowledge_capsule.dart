/// ───────────────────────────────────────────────────────────────────────────
/// Offline Knowledge Capsule for SAHA-Quantum.
///
/// In zero-network villages, the phone becomes a **micro knowledge node**.
///
/// This module provides:
///   1. **Embedded Medical Decision Support** — protocol-driven screening
///      summaries with clinical thresholds and action paths.
///   2. **WHO Screening Guidelines** — locally cached, structured
///      guideline data for oral cancer and TB screening.
///   3. **Treatment Protocol Suggestions** — non-prescriptive, evidence-
///      based suggestions aligned with ICMR/WHO/RNTCP standards.
///   4. **Drug Reference** — essential drug information for common
///      conditions encountered at PHC/CHC level.
///   5. **IEC Materials** — patient-facing Information, Education, and
///      Communication summaries in simple language.
///
/// All data is embedded in the binary — **zero network required**.
/// Content aligned with:
///   - WHO Oral Health Surveys (5th Edition, 2013)
///   - RNTCP Technical & Operational Guidelines (2016)
///   - ICMR Guidelines for Oral Cancer Screening (2022)
///   - National Programme for Prevention and Control of Cancer (NPCC)
/// ───────────────────────────────────────────────────────────────────────────
class OfflineKnowledgeCapsule {
  OfflineKnowledgeCapsule._();
  static final OfflineKnowledgeCapsule instance =
      OfflineKnowledgeCapsule._();

  // ════════════════════════════════════════════════════════════════════════
  //  ORAL CANCER KNOWLEDGE BASE
  // ════════════════════════════════════════════════════════════════════════

  static const oralCancerGuidelines = KnowledgeModule(
    id: 'oral-cancer-guidelines',
    title: 'Oral Cancer Screening Guidelines',
    source: 'WHO / ICMR / NPCC 2022',
    lastUpdated: '2025-11-01',
    sections: [
      KnowledgeSection(
        title: 'Overview',
        content:
            'Oral cancer is the most common cancer among men in India, '
            'accounting for approximately 30% of all new cancer cases. '
            'Over 77,000 new cases are diagnosed annually. Early detection '
            'through visual screening by trained health workers reduces '
            'mortality by 32% (Sankaranarayanan et al., Lancet 2005).',
      ),
      KnowledgeSection(
        title: 'Risk Factors',
        content:
            '• Tobacco use (all forms — smoking, chewing, gutka, khaini)\n'
            '• Betel nut / areca nut chewing (pan masala)\n'
            '• Heavy alcohol consumption\n'
            '• HPV infection (types 16, 18)\n'
            '• Chronic sun exposure (lip cancer)\n'
            '• Age > 40 years\n'
            '• Poor oral hygiene\n'
            '• Nutritional deficiencies (iron, vitamin A, C)',
      ),
      KnowledgeSection(
        title: 'Visual Screening Protocol (WHO)',
        content:
            '1. Ask patient to open mouth wide under good light\n'
            '2. Examine all six regions systematically:\n'
            '   a. Lips (outer and inner surface)\n'
            '   b. Buccal mucosa (inner cheeks)\n'
            '   c. Tongue (dorsal, ventral, lateral surfaces)\n'
            '   d. Floor of mouth\n'
            '   e. Hard and soft palate\n'
            '   f. Gingiva (gums)\n'
            '3. Palpate for lymph nodes (submandibular, cervical)\n'
            '4. Document all lesions with photographs\n'
            '5. Use SAHA AI for objective second opinion',
      ),
      KnowledgeSection(
        title: 'Red Flag Lesions (Requires Immediate Referral)',
        content:
            '• Leukoplakia — white patches that do not rub off\n'
            '• Erythroplakia — red velvet-like patches\n'
            '• Oral submucous fibrosis — restricted mouth opening\n'
            '• Non-healing ulcers > 2 weeks duration\n'
            '• Lumps or hard masses in oral cavity\n'
            '• Persistent sore throat or hoarseness > 3 weeks\n'
            '• Difficulty swallowing (dysphagia)\n'
            '• Unexplained bleeding or numbness',
      ),
      KnowledgeSection(
        title: 'Staging & Referral Pathways',
        content:
            'LOW risk (Normal): Annual rescreening\n'
            'MEDIUM risk (Suspicious): Rescreen in 3 months + counseling\n'
            'HIGH risk (Probable lesion): Refer to District Hospital ENT '
            'within 7 days for biopsy\n'
            'CRITICAL risk (Likely malignancy): Emergency referral to '
            'Regional Cancer Centre within 24 hours',
      ),
      KnowledgeSection(
        title: 'Prevention Counseling Points',
        content:
            '• Tobacco cessation is the single most effective prevention\n'
            '• Offer Quitline number: 1800-11-2356 (NTCP)\n'
            '• Diet rich in fruits, vegetables, and antioxidants\n'
            '• Regular dental check-ups (at least annual)\n'
            '• Limit alcohol consumption\n'
            '• Daily oral self-examination (mirror technique)\n'
            '• Maintain good oral hygiene (brush 2×/day, floss)',
      ),
    ],
  );

  // ════════════════════════════════════════════════════════════════════════
  //  TUBERCULOSIS KNOWLEDGE BASE
  // ════════════════════════════════════════════════════════════════════════

  static const tbGuidelines = KnowledgeModule(
    id: 'tb-guidelines',
    title: 'Tuberculosis Screening Guidelines',
    source: 'WHO / RNTCP / NTEP 2024',
    lastUpdated: '2025-11-01',
    sections: [
      KnowledgeSection(
        title: 'Overview',
        content:
            'India accounts for 28% of global TB cases with approximately '
            '2.8 million new cases annually. Under the National TB '
            'Elimination Programme (NTEP), India aims to eliminate TB '
            'by 2025. Active case finding through community screening '
            'is a key strategy.',
      ),
      KnowledgeSection(
        title: 'Symptoms Checklist',
        content:
            'Screen for any of the following (WHO 4-symptom screen):\n'
            '• Cough of any duration (previously > 2 weeks; now any cough '
            'is considered in high-prevalence settings)\n'
            '• Fever, especially evening rise\n'
            '• Night sweats\n'
            '• Unexplained weight loss\n\n'
            'Sensitivity of 4-symptom screen: ~90% for pulmonary TB',
      ),
      KnowledgeSection(
        title: 'SAHA AI Cough Analysis Protocol',
        content:
            '1. Record a 3–5 second cough sample in a quiet environment\n'
            '2. Position the phone 30cm from the patient\'s mouth\n'
            '3. Patient should cough naturally (forced if needed)\n'
            '4. SAHA AI analyzes acoustic biomarkers:\n'
            '   - MFCC spectral features\n'
            '   - Cough intensity patterns\n'
            '   - Temporal characteristics\n'
            '5. AI provides probability assessment (NOT diagnosis)\n'
            '6. TB Indicative result requires confirmatory testing',
      ),
      KnowledgeSection(
        title: 'Confirmatory Testing Pathway',
        content:
            'If AI screening is positive:\n'
            '1. Collect 2 sputum samples (spot + early morning)\n'
            '2. Send for CBNAAT/GeneXpert (preferred) or AFB smear\n'
            '3. CBNAAT provides result in 2 hours + rifampicin resistance\n'
            '4. If CBNAAT unavailable: TrueNat at PHC level\n'
            '5. Chest X-ray at CHC/DH if sputum negative\n'
            '6. Notify all confirmed cases via NIKSHAY portal',
      ),
      KnowledgeSection(
        title: 'DOTS Treatment Protocol (Category I)',
        content:
            'New patients (drug-susceptible TB):\n'
            '• Intensive Phase (2 months): HRZE\n'
            '  H = Isoniazid, R = Rifampicin, Z = Pyrazinamide, '
            'E = Ethambutol\n'
            '• Continuation Phase (4 months): HR\n'
            '• Total duration: 6 months\n'
            '• Daily regimen (weight-based dosing)\n'
            '• DOT by health worker or treatment supporter\n\n'
            'NOTE: This is NON-PRESCRIPTIVE guidance. '
            'Only qualified physicians should initiate ATT.',
      ),
      KnowledgeSection(
        title: 'Infection Control (IPC)',
        content:
            '• Cough hygiene: cover mouth/nose when coughing\n'
            '• Adequate ventilation in living spaces\n'
            '• Separate sleeping arrangements during infectious period\n'
            '• N95 masks for healthcare workers during procedures\n'
            '• UV germicidal irradiation (UVGI) in health facilities\n'
            '• Screen household contacts (children < 5 at highest risk)',
      ),
    ],
  );

  // ════════════════════════════════════════════════════════════════════════
  //  ESSENTIAL DRUG REFERENCE
  // ════════════════════════════════════════════════════════════════════════

  static const drugReference = [
    DrugInfo(
      name: 'Isoniazid (H)',
      category: 'Anti-tubercular',
      indication: 'Tuberculosis (all forms)',
      dosage: '5 mg/kg/day (max 300mg)',
      sideEffects: 'Hepatotoxicity, peripheral neuropathy',
      contraindications: 'Active hepatitis, severe liver disease',
      note: 'Give with Pyridoxine (Vitamin B6) to prevent neuropathy',
    ),
    DrugInfo(
      name: 'Rifampicin (R)',
      category: 'Anti-tubercular',
      indication: 'Tuberculosis (all forms)',
      dosage: '10 mg/kg/day (max 600mg)',
      sideEffects: 'Orange discoloration of urine, hepatotoxicity',
      contraindications: 'Jaundice, drug interactions with OCP',
      note: 'Take on empty stomach; turns urine red-orange (normal)',
    ),
    DrugInfo(
      name: 'Metronidazole',
      category: 'Antimicrobial',
      indication: 'Oral infections, anaerobic infections',
      dosage: '400mg TDS × 5 days',
      sideEffects: 'Metallic taste, nausea, dark urine',
      contraindications: 'Alcohol use (disulfiram reaction)',
      note: 'Warn patient: absolutely no alcohol during treatment',
    ),
    DrugInfo(
      name: 'Paracetamol',
      category: 'Analgesic / Antipyretic',
      indication: 'Pain, fever',
      dosage: '500-1000mg QDS (max 4g/day)',
      sideEffects: 'Hepatotoxicity at high doses',
      contraindications: 'Severe liver impairment',
      note: 'Safe in pregnancy; first-line for mild-moderate pain',
    ),
    DrugInfo(
      name: 'Chlorhexidine Mouthwash',
      category: 'Oral antiseptic',
      indication: 'Oral lesions, post-procedure care',
      dosage: '10ml rinse BD × 14 days',
      sideEffects: 'Tooth staining, taste alteration',
      contraindications: 'Known hypersensitivity',
      note: 'Do not eat/drink for 30 min after use',
    ),
  ];

  // ════════════════════════════════════════════════════════════════════════
  //  IEC (Information, Education, Communication) — Patient-Facing
  // ════════════════════════════════════════════════════════════════════════

  static const patientEducation = [
    IECCard(
      id: 'iec-oral-self-exam',
      title: 'How to Check Your Mouth at Home',
      content:
          '1. Stand in front of a mirror with good light\n'
          '2. Pull your lower lip down — look for sores or colour changes\n'
          '3. Pull each cheek out — check the inner lining\n'
          '4. Stick your tongue out — look at the top, bottom, and sides\n'
          '5. Tilt your head back — look at the roof of your mouth\n'
          '6. Feel your neck for any lumps\n\n'
          'If you find any sore that doesn\'t heal in 2 weeks, '
          'see a doctor immediately.',
      category: 'Oral Cancer',
    ),
    IECCard(
      id: 'iec-tb-awareness',
      title: 'What is TB? (Patient Guide)',
      content:
          'TB (Tuberculosis) is caused by germs that spread through air '
          'when a person with TB coughs or sneezes.\n\n'
          'TB CAN be cured with 6 months of proper medicine.\n'
          'TB treatment is FREE in India at all government hospitals.\n\n'
          'If you have a cough for more than 2 weeks, get tested.\n'
          'Take ALL your medicines for the FULL 6 months — '
          'even if you feel better early.\n\n'
          'Call TB Helpline: 1800-11-6666 (toll-free)',
      category: 'Tuberculosis',
    ),
    IECCard(
      id: 'iec-tobacco-quit',
      title: 'Quitting Tobacco — You Can Do It!',
      content:
          'Benefits of quitting:\n'
          '• Within 20 minutes: heart rate drops\n'
          '• Within 12 hours: carbon monoxide in blood drops\n'
          '• Within 2-3 months: circulation and lung function improve\n'
          '• Within 1 year: heart disease risk drops to half\n'
          '• Within 5 years: mouth cancer risk drops to half\n\n'
          'Free help: Quitline 1800-11-2356\n'
          'Or SMS QUIT to 011-22901701',
      category: 'Prevention',
    ),
    IECCard(
      id: 'iec-nutrition',
      title: 'Diet for Healthy Mouth & Lungs',
      content:
          'Eat MORE of:\n'
          '• Green leafy vegetables (spinach, methi, palak)\n'
          '• Colourful fruits (papaya, guava, amla, orange)\n'
          '• Whole grains (roti, brown rice, bajra)\n'
          '• Milk, curd, paneer (for calcium)\n'
          '• Dal, sprouts, eggs (for protein)\n\n'
          'Eat LESS of:\n'
          '• Very spicy or very hot food\n'
          '• Processed/packaged food\n'
          '• Sugary drinks\n'
          '• Alcohol',
      category: 'Nutrition',
    ),
  ];

  // ════════════════════════════════════════════════════════════════════════
  //  EMERGENCY NUMBERS
  // ════════════════════════════════════════════════════════════════════════

  static const emergencyNumbers = [
    EmergencyContact(name: 'National Emergency', number: '112'),
    EmergencyContact(name: 'Ambulance', number: '108'),
    EmergencyContact(
        name: 'TB Helpline', number: '1800-11-6666'),
    EmergencyContact(
        name: 'Tobacco Quitline', number: '1800-11-2356'),
    EmergencyContact(
        name: 'National Cancer Helpline', number: '1800-11-5500'),
    EmergencyContact(
        name: 'ABDM/ABHA Helpline', number: '1800-11-4477'),
    EmergencyContact(
        name: 'Poison Info Centre (AIIMS)', number: '011-26593677'),
  ];

  // ════════════════════════════════════════════════════════════════════════
  //  SEARCH / ACCESS METHODS
  // ════════════════════════════════════════════════════════════════════════

  /// Get guidelines for a specific screening type.
  KnowledgeModule getGuidelines(String screeningType) {
    if (screeningType == 'oral_cancer') return oralCancerGuidelines;
    if (screeningType == 'tb_cough') return tbGuidelines;
    return oralCancerGuidelines; // default
  }

  /// Search all knowledge content.
  List<SearchResult> search(String query) {
    final results = <SearchResult>[];
    final q = query.toLowerCase();

    // Search guidelines
    for (final module in [oralCancerGuidelines, tbGuidelines]) {
      for (final section in module.sections) {
        if (section.title.toLowerCase().contains(q) ||
            section.content.toLowerCase().contains(q)) {
          results.add(SearchResult(
            title: '${module.title} — ${section.title}',
            snippet: section.content.substring(
                0, section.content.length > 120 ? 120 : section.content.length),
            source: module.source,
            category: 'Guidelines',
          ));
        }
      }
    }

    // Search drug reference
    for (final drug in drugReference) {
      if (drug.name.toLowerCase().contains(q) ||
          drug.indication.toLowerCase().contains(q)) {
        results.add(SearchResult(
          title: drug.name,
          snippet: '${drug.indication} — ${drug.dosage}',
          source: 'Drug Reference',
          category: 'Drugs',
        ));
      }
    }

    // Search IEC
    for (final card in patientEducation) {
      if (card.title.toLowerCase().contains(q) ||
          card.content.toLowerCase().contains(q)) {
        results.add(SearchResult(
          title: card.title,
          snippet: card.content.substring(
              0, card.content.length > 120 ? 120 : card.content.length),
          source: 'Patient Education',
          category: card.category,
        ));
      }
    }

    return results;
  }

  /// Get all knowledge modules.
  List<KnowledgeModule> get allModules =>
      [oralCancerGuidelines, tbGuidelines];

  /// Get all patient education cards.
  List<IECCard> get allIECCards => patientEducation;
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class KnowledgeModule {
  const KnowledgeModule({
    required this.id,
    required this.title,
    required this.source,
    required this.lastUpdated,
    required this.sections,
  });

  final String id;
  final String title;
  final String source;
  final String lastUpdated;
  final List<KnowledgeSection> sections;
}

class KnowledgeSection {
  const KnowledgeSection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

class DrugInfo {
  const DrugInfo({
    required this.name,
    required this.category,
    required this.indication,
    required this.dosage,
    required this.sideEffects,
    required this.contraindications,
    required this.note,
  });

  final String name;
  final String category;
  final String indication;
  final String dosage;
  final String sideEffects;
  final String contraindications;
  final String note;
}

class IECCard {
  const IECCard({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
  });

  final String id;
  final String title;
  final String content;
  final String category;
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.number,
  });

  final String name;
  final String number;
}

class SearchResult {
  const SearchResult({
    required this.title,
    required this.snippet,
    required this.source,
    required this.category,
  });

  final String title;
  final String snippet;
  final String source;
  final String category;
}

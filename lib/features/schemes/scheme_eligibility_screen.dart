import 'package:flutter/material.dart';

/// Government Health Scheme Eligibility Checker.
///
/// Allows citizens to enter their details and check eligibility for
/// major Indian government health insurance / welfare schemes:
///   • Ayushman Bharat PM-JAY (Pradhan Mantri Jan Arogya Yojana)
///   • CGHS (Central Government Health Scheme)
///   • ESI (Employees' State Insurance)
///   • RSBY (Rashtriya Swasthya Bima Yojana)
///   • Janani Suraksha Yojana
///   • National Health Mission programmes
///   • State-specific schemes
class SchemeEligibilityScreen extends StatefulWidget {
  const SchemeEligibilityScreen({super.key});

  @override
  State<SchemeEligibilityScreen> createState() =>
      _SchemeEligibilityScreenState();
}

class _SchemeEligibilityScreenState extends State<SchemeEligibilityScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  String _name = '';
  int? _age;
  String _gender = 'Male';
  String _state = 'Select State';
  String _category = 'General';
  double? _annualIncome;
  bool _isBPL = false;
  bool _isRural = false;
  String _occupation = 'Self-employed';
  String _rationCardType = 'None';
  bool _isPregnant = false;
  bool _hasDisability = false;
  int _familySize = 4;

  // Results
  List<SchemeResult>? _results;
  bool _isChecking = false;

  static const _saffron = Color(0xFFFF9933);
  static const _navyBlue = Color(0xFF000080);
  static const _green = Color(0xFF138808);

  static const _states = [
    'Select State',
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Delhi',
    'Jammu & Kashmir',
    'Ladakh',
    'Puducherry',
    'Chandigarh',
  ];

  static const _categories = [
    'General',
    'OBC',
    'SC',
    'ST',
    'EWS',
  ];

  static const _occupations = [
    'Self-employed',
    'Government Employee',
    'Private Sector Employee',
    'Farmer / Agricultural Worker',
    'Daily Wage Labourer',
    'Student',
    'Homemaker',
    'Unemployed',
    'Retired',
    'Armed Forces',
  ];

  static const _rationCardTypes = [
    'None',
    'AAY (Antyodaya)',
    'BPL (Below Poverty Line)',
    'APL (Above Poverty Line)',
    'PHH (Priority Household)',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Scheme Eligibility'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header Banner ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_saffron, Color(0xFFFFA64D)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _saffron.withAlpha(60),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(50),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.health_and_safety,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Check Your Eligibility',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Enter your details below to find government '
                          'health schemes you may be eligible for.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Form ──────────────────────────────────────────
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader('Personal Details', Icons.person),
                  const SizedBox(height: 12),

                  // Name
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    onChanged: (v) => _name = v,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // Age + Gender row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Age',
                            prefixIcon: Icon(Icons.cake_outlined),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _age = int.tryParse(v),
                          validator: (v) {
                            final age = int.tryParse(v ?? '');
                            if (age == null || age < 0 || age > 120) {
                              return 'Valid age';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.wc),
                          ),
                          items: ['Male', 'Female', 'Other']
                              .map((g) =>
                                  DropdownMenuItem(value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) => setState(() => _gender = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // State
                  DropdownButtonFormField<String>(
                    value: _state,
                    decoration: const InputDecoration(
                      labelText: 'State / UT',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: _states
                        .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _state = v!),
                    validator: (v) =>
                        v == 'Select State' ? 'Select your state' : null,
                  ),
                  const SizedBox(height: 12),

                  // Category
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: _categories
                        .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),

                  const SizedBox(height: 20),
                  _buildSectionHeader(
                      'Economic Details', Icons.account_balance_wallet),
                  const SizedBox(height: 12),

                  // Annual Income
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Annual Family Income (₹)',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _annualIncome = double.tryParse(v),
                  ),
                  const SizedBox(height: 12),

                  // Occupation
                  DropdownButtonFormField<String>(
                    value: _occupation,
                    decoration: const InputDecoration(
                      labelText: 'Occupation',
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                    items: _occupations
                        .map(
                            (o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) => setState(() => _occupation = v!),
                  ),
                  const SizedBox(height: 12),

                  // Ration Card
                  DropdownButtonFormField<String>(
                    value: _rationCardType,
                    decoration: const InputDecoration(
                      labelText: 'Ration Card Type',
                      prefixIcon: Icon(Icons.card_membership),
                    ),
                    items: _rationCardTypes
                        .map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _rationCardType = v!;
                      _isBPL = v == 'BPL (Below Poverty Line)' ||
                          v == 'AAY (Antyodaya)';
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Family Size
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Family Size',
                            style: TextStyle(fontSize: 14)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _familySize > 1
                            ? () => setState(() => _familySize--)
                            : null,
                      ),
                      Text('$_familySize',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _familySize < 15
                            ? () => setState(() => _familySize++)
                            : null,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _buildSectionHeader(
                      'Additional Details', Icons.info_outline),
                  const SizedBox(height: 12),

                  // Toggle switches
                  _buildSwitch('Below Poverty Line (BPL)', _isBPL,
                      (v) => setState(() => _isBPL = v)),
                  _buildSwitch('Rural Area Resident', _isRural,
                      (v) => setState(() => _isRural = v)),
                  if (_gender == 'Female')
                    _buildSwitch('Currently Pregnant', _isPregnant,
                        (v) => setState(() => _isPregnant = v)),
                  _buildSwitch('Person with Disability', _hasDisability,
                      (v) => setState(() => _hasDisability = v)),

                  const SizedBox(height: 24),

                  // ── Check Button ────────────────────────────
                  FilledButton.icon(
                    onPressed: _isChecking ? null : _checkEligibility,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                        _isChecking ? 'Checking…' : 'Check Eligibility'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],
              ),
            ),

            // ── Results ───────────────────────────────────────
            if (_results != null) ...[
              const SizedBox(height: 24),
              _buildResultsSection(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _navyBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _navyBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeColor: _green,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  void _checkEligibility() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isChecking = true);

    // Simulate processing delay
    Future.delayed(const Duration(milliseconds: 800), () {
      final results = _evaluateSchemes();
      if (mounted) {
        setState(() {
          _results = results;
          _isChecking = false;
        });
      }
    });
  }

  List<SchemeResult> _evaluateSchemes() {
    final results = <SchemeResult>[];
    final income = _annualIncome ?? 0;

    // ── 1. Ayushman Bharat PM-JAY ─────────────────────────
    // Covers ₹5 lakh per family per year for secondary/tertiary care
    // Eligibility: SECC 2011 deprivation criteria, BPL families
    final pmjayEligible = _isBPL ||
        income <= 500000 ||
        _category == 'SC' ||
        _category == 'ST' ||
        _rationCardType == 'AAY (Antyodaya)' ||
        _rationCardType == 'BPL (Below Poverty Line)' ||
        _occupation == 'Daily Wage Labourer';
    results.add(SchemeResult(
      name: 'Ayushman Bharat PM-JAY',
      fullName: 'Pradhan Mantri Jan Arogya Yojana',
      eligible: pmjayEligible,
      coverage: '₹5,00,000 per family per year',
      description:
          'Cashless & paperless secondary and tertiary care hospitalisation '
          'at empanelled hospitals across India. Covers 1,929+ procedures '
          'including surgery, medical packages, and day-care treatments.',
      benefits: [
        '₹5 Lakh coverage per family per year',
        'Cashless treatment at empanelled hospitals',
        '1,929+ medical/surgical packages',
        'No restriction on family size',
        'Pre & post hospitalisation expenses covered',
      ],
      howToApply:
          'Visit nearest Common Service Centre (CSC) or Ayushman Mitra '
          'at empanelled hospital with Aadhaar card. Apply online at '
          'pmjay.gov.in or call 14555.',
      icon: Icons.local_hospital,
      color: _saffron,
    ));

    // ── 2. CGHS ───────────────────────────────────────────
    final cghs = _occupation == 'Government Employee' ||
        _occupation == 'Retired' ||
        _occupation == 'Armed Forces';
    results.add(SchemeResult(
      name: 'CGHS',
      fullName: 'Central Government Health Scheme',
      eligible: cghs,
      coverage: 'Comprehensive (Ward entitlement based on pay)',
      description:
          'Comprehensive healthcare for Central Government employees, '
          'pensioners, and their dependents. Covers OPD, hospitalisation, '
          'diagnostics, and pharmacy.',
      benefits: [
        'OPD consultation at CGHS dispensaries',
        'Hospitalisation at empanelled hospitals',
        'Medicines from CGHS pharmacies',
        'Diagnostic tests and investigations',
        'Coverage for dependents',
      ],
      howToApply:
          'Apply through your department/ministry. Pensioners can apply '
          'at the nearest CGHS city office with PPO and Aadhaar.',
      icon: Icons.account_balance,
      color: _navyBlue,
    ));

    // ── 3. ESI ────────────────────────────────────────────
    final esi = _occupation == 'Private Sector Employee' &&
        income <= 2100000; // ₹21,000/month
    results.add(SchemeResult(
      name: 'ESI Scheme',
      fullName: 'Employees\' State Insurance Scheme',
      eligible: esi,
      coverage: 'Full medical care for employee & family',
      description:
          'Social security scheme for workers in the organised sector '
          'earning up to ₹21,000/month. Provides medical, sickness, '
          'maternity, disability and dependant benefits.',
      benefits: [
        'Free medical care at ESI hospitals & dispensaries',
        'Sickness benefit: 70% of wages',
        'Maternity benefit: 100% of wages for 26 weeks',
        'Disablement benefit (temporary & permanent)',
        'Dependant benefit for family of deceased',
      ],
      howToApply:
          'Employer registers on esic.gov.in. Employee receives '
          'ESI card with biometric. Visit nearest ESIC branch office.',
      icon: Icons.business,
      color: const Color(0xFF1976D2),
    ));

    // ── 4. Janani Suraksha Yojana ─────────────────────────
    final jsy = _gender == 'Female' &&
        (_isPregnant || (_age != null && _age! >= 18 && _age! <= 45)) &&
        (_isBPL || _isRural || _category == 'SC' || _category == 'ST');
    results.add(SchemeResult(
      name: 'Janani Suraksha Yojana',
      fullName: 'Janani Suraksha Yojana (JSY)',
      eligible: jsy,
      coverage: 'Cash assistance for institutional delivery',
      description:
          'Safe motherhood intervention under NHM. Provides cash assistance '
          'for institutional delivery, especially for BPL pregnant women.',
      benefits: [
        'Rural: ₹1,400 cash for mother + ₹600 for ASHA',
        'Urban: ₹1,000 cash for mother + ₹400 for ASHA',
        'Free delivery and C-section at government hospitals',
        'Transport assistance',
        'Post-natal care visits',
      ],
      howToApply:
          'Register at nearest Government hospital/PHC/Sub-centre. '
          'Contact your local ASHA worker or ANM.',
      icon: Icons.pregnant_woman,
      color: const Color(0xFFE91E63),
    ));

    // ── 5. Pradhan Mantri Suraksha Bima Yojana ────────────
    final pmsby = _age != null && _age! >= 18 && _age! <= 70;
    results.add(SchemeResult(
      name: 'PM Suraksha Bima Yojana',
      fullName: 'Pradhan Mantri Suraksha Bima Yojana',
      eligible: pmsby,
      coverage: '₹2 Lakh accidental death/disability @ ₹20/year',
      description:
          'Accident insurance scheme at just ₹20 per year. Available to '
          'all bank account holders aged 18-70.',
      benefits: [
        '₹2 Lakh for accidental death',
        '₹2 Lakh for total permanent disability',
        '₹1 Lakh for partial permanent disability',
        'Premium: only ₹20/year (auto-debit from bank)',
        'Available at any bank/post office',
      ],
      howToApply:
          'Apply at your bank branch or via net banking. Auto-debit of '
          '₹20 annually from your savings account.',
      icon: Icons.shield,
      color: const Color(0xFF00897B),
    ));

    // ── 6. PM Jeevan Jyoti Bima Yojana ───────────────────
    final pmjjby = _age != null && _age! >= 18 && _age! <= 50;
    results.add(SchemeResult(
      name: 'PM Jeevan Jyoti Bima',
      fullName: 'Pradhan Mantri Jeevan Jyoti Bima Yojana',
      eligible: pmjjby,
      coverage: '₹2 Lakh life insurance @ ₹436/year',
      description:
          'Life insurance scheme at ₹436 per year for bank account holders '
          'aged 18-50. Provides ₹2 Lakh on death due to any reason.',
      benefits: [
        '₹2 Lakh life cover for death due to any reason',
        'Premium: ₹436/year (auto-debit from bank)',
        'No medical examination required',
        'Available at any commercial/RRB bank',
      ],
      howToApply:
          'Opt-in at your bank branch or via net banking/mobile app.',
      icon: Icons.favorite,
      color: const Color(0xFFD32F2F),
    ));

    // ── 7. National AYUSH Mission ─────────────────────────
    results.add(SchemeResult(
      name: 'National AYUSH Mission',
      fullName: 'National AYUSH Mission (NAM)',
      eligible: true, // available to all
      coverage: 'Free AYUSH treatment at government centres',
      description:
          'Provides affordable access to Ayurveda, Yoga, Unani, Siddha '
          'and Homoeopathy (AYUSH) services through government centres.',
      benefits: [
        'Free AYUSH consultations',
        'Subsidised AYUSH medicines',
        'Yoga & wellness programmes',
        'AYUSH Health & Wellness Centres',
        'Integration with primary healthcare',
      ],
      howToApply:
          'Visit nearest AYUSH Health & Wellness Centre or government '
          'AYUSH hospital. No registration needed.',
      icon: Icons.spa,
      color: const Color(0xFF388E3C),
    ));

    // ── 8. State Health Insurance (generic) ───────────────
    final stateSchemeEligible =
        income <= 300000 || _isBPL || _category != 'General';
    String stateScheme = 'State Health Insurance';
    String stateDesc = 'Your state may offer additional health schemes.';
    if (_state == 'Tamil Nadu') {
      stateScheme = 'Chief Minister\'s Health Insurance (CMCHISTN)';
      stateDesc =
          'Covers ₹5 Lakh for 1,027 procedures at empanelled hospitals.';
    } else if (_state == 'Kerala') {
      stateScheme = 'Karunya Health Scheme';
      stateDesc =
          'Covers BPL families for critical illnesses like cancer, '
          'cardiac surgery, and organ transplant.';
    } else if (_state == 'Rajasthan') {
      stateScheme = 'Chiranjeevi Health Insurance';
      stateDesc =
          'Covers ₹25 Lakh for any Rajasthan family at ₹850/year. '
          'Free for BPL, small/marginal farmers, and NFSA beneficiaries.';
    } else if (_state == 'Maharashtra') {
      stateScheme = 'Mahatma Phule Jan Arogya Yojana';
      stateDesc =
          'Covers ₹1.5 Lakh per family for 996 surgeries/treatments '
          'at 497 empanelled hospitals.';
    } else if (_state == 'Andhra Pradesh' || _state == 'Telangana') {
      stateScheme = 'Dr. YSR Aarogyasri / Aarogyasri';
      stateDesc =
          'Covers BPL families for critical illnesses including cancer, '
          'cardiac, and neuro surgeries up to ₹5 Lakh.';
    } else if (_state == 'Karnataka') {
      stateScheme = 'Yeshasvini Health Insurance';
      stateDesc =
          'Cooperative societies members can avail surgeries at '
          'empanelled hospitals at ₹350/year.';
    } else if (_state == 'West Bengal') {
      stateScheme = 'Swasthya Sathi';
      stateDesc =
          'Covers ₹5 Lakh per family per year for secondary/tertiary care. '
          'Universal — covers all West Bengal families.';
    }
    results.add(SchemeResult(
      name: stateScheme,
      fullName: 'State Health Insurance Scheme',
      eligible: stateSchemeEligible,
      coverage: 'Varies by state',
      description: stateDesc,
      benefits: [
        'Cashless treatment at empanelled hospitals',
        'Coverage for hospitalisation & surgeries',
        'Varies by state — check your state portal',
      ],
      howToApply:
          'Visit your state health department website or nearest '
          'district/block office for registration.',
      icon: Icons.map,
      color: const Color(0xFF7B1FA2),
    ));

    // ── 9. Disability Support ─────────────────────────────
    if (_hasDisability) {
      results.add(SchemeResult(
        name: 'Disability Pension Scheme',
        fullName: 'Indira Gandhi National Disability Pension Scheme',
        eligible: true,
        coverage: '₹300/month pension',
        description:
            'Monthly pension for persons with severe disabilities (80% or more) '
            'belonging to BPL families, aged 18-79 years.',
        benefits: [
          '₹300/month from Central Government',
          'Additional ₹200-500/month from state (varies)',
          'Free disability certificate at government hospitals',
          'Concession in travel, education, taxation',
        ],
        howToApply:
            'Apply at Block/District Social Welfare office with '
            'disability certificate (40%+) from Chief Medical Officer.',
        icon: Icons.accessible,
        color: const Color(0xFF546E7A),
      ));
    }

    // Sort: eligible first
    results.sort((a, b) {
      if (a.eligible && !b.eligible) return -1;
      if (!a.eligible && b.eligible) return 1;
      return 0;
    });

    return results;
  }

  Widget _buildResultsSection(ThemeData theme) {
    final eligible = _results!.where((r) => r.eligible).toList();
    final notEligible = _results!.where((r) => !r.eligible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _green.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green.withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: _green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You may be eligible for ${eligible.length} scheme${eligible.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _green,
                      ),
                    ),
                    if (_name.isNotEmpty)
                      Text(
                        'Results for $_name',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Eligible schemes
        if (eligible.isNotEmpty) ...[
          const Text(
            'ELIGIBLE SCHEMES',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _green,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ...eligible.map((s) => _buildSchemeCard(s, true)),
        ],

        if (notEligible.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'OTHER SCHEMES',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ...notEligible.map((s) => _buildSchemeCard(s, false)),
        ],

        const SizedBox(height: 20),

        // Disclaimer
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This is an indicative eligibility check based on general '
                  'criteria. Final eligibility is determined by the respective '
                  'scheme authority. Please visit the official scheme portal '
                  'or nearest government office for confirmation.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSchemeCard(SchemeResult scheme, bool isEligible) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isEligible ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isEligible ? scheme.color.withAlpha(80) : Colors.grey.shade200,
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isEligible ? scheme.color : Colors.grey).withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: Icon(
            scheme.icon,
            color: isEligible ? scheme.color : Colors.grey,
            size: 22,
          ),
        ),
        title: Text(
          scheme.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isEligible ? Colors.black87 : Colors.grey.shade500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scheme.coverage,
              style: TextStyle(
                fontSize: 12,
                color: isEligible ? scheme.color : Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isEligible)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _green.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '✓ Likely Eligible',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheme.description,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Key Benefits:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                ...scheme.benefits.map((b) => Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check, size: 14, color: scheme.color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(b,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _navyBlue.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.how_to_reg, size: 16, color: _navyBlue),
                          SizedBox(width: 6),
                          Text(
                            'How to Apply:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _navyBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scheme.howToApply,
                        style: const TextStyle(
                            fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A government health scheme eligibility result.
class SchemeResult {
  const SchemeResult({
    required this.name,
    required this.fullName,
    required this.eligible,
    required this.coverage,
    required this.description,
    required this.benefits,
    required this.howToApply,
    required this.icon,
    required this.color,
  });

  final String name;
  final String fullName;
  final bool eligible;
  final String coverage;
  final String description;
  final List<String> benefits;
  final String howToApply;
  final IconData icon;
  final Color color;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/audit/audit_trail_screen.dart';
import '../features/district/district_dashboard_screen.dart';
import '../features/federated/fl_dashboard_screen.dart';
import '../features/fraud/fraud_alerts_screen.dart';
import '../features/governance/governance_screen.dart';
import '../features/knowledge/knowledge_screen.dart';
import '../features/language/language_screen.dart';
import '../features/mesh/mesh_screen.dart';
import '../features/patient/screens/patient_detail_screen.dart';
import '../features/patient/screens/patient_list_screen.dart';
import '../features/patient/screens/registration_screen.dart';
import '../features/privacy/privacy_screen.dart';
import '../features/provisioning/provisioning_screen.dart';
import '../features/risk/risk_dashboard_screen.dart';
import '../features/schemes/scheme_eligibility_screen.dart';
import '../features/screening/cancer/screens/oral_scan_screen.dart';
import '../features/screening/tb/screens/cough_record_screen.dart';
import '../features/showcase/gesture_talk_screen.dart';
import '../features/showcase/smart_triage_screen.dart';
import 'home_screen.dart';
import 'splash_screen.dart';

/// Application route configuration using [GoRouter].
///
/// All routes work offline — no network guard.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: true,
  routes: [
    // ── Splash Screen (Indian Govt Theme) ────────────────────
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => SplashScreen(
        onFinished: () => context.go('/'),
      ),
    ),

    // ── Home / Dashboard ─────────────────────────────────────
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),

    // ── Patients ─────────────────────────────────────────────
    GoRoute(
      path: '/patients',
      name: 'patients',
      builder: (context, state) => const PatientListScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(
      path: '/patient/:id',
      name: 'patientDetail',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return PatientDetailScreen(patientId: id);
      },
    ),

    // ── Screenings ───────────────────────────────────────────
    GoRoute(
      path: '/screening/cancer/:patientId',
      name: 'cancerScreening',
      builder: (context, state) {
        final pid = state.pathParameters['patientId']!;
        return OralScanScreen(patientId: pid);
      },
    ),
    GoRoute(
      path: '/screening/tb/:patientId',
      name: 'tbScreening',
      builder: (context, state) {
        final pid = state.pathParameters['patientId']!;
        return CoughRecordScreen(patientId: pid);
      },
    ),

    // ── P2P Mesh Network ─────────────────────────────────────
    GoRoute(
      path: '/mesh',
      name: 'mesh',
      builder: (context, state) => const MeshNetworkScreen(),
    ),

    // ── Federated Learning ───────────────────────────────────
    GoRoute(
      path: '/federated',
      name: 'federated',
      builder: (context, state) => const FlDashboardScreen(),
    ),

    // ── SAHI/BODH Audit Trail ────────────────────────────────
    GoRoute(
      path: '/audit',
      name: 'audit',
      builder: (context, state) => const AuditTrailScreen(),
    ),

    // ── NAFU-Lite Fraud Alerts ───────────────────────────────
    GoRoute(
      path: '/fraud',
      name: 'fraud',
      builder: (context, state) => const FraudAlertsScreen(),
    ),

    // ── Bhashini Language Selection ──────────────────────────
    GoRoute(
      path: '/language',
      name: 'language',
      builder: (context, state) => const LanguageScreen(),
    ),

    // ── Model Lifecycle Governance ───────────────────────────
    GoRoute(
      path: '/governance',
      name: 'governance',
      builder: (context, state) => const GovernanceScreen(),
    ),

    // ── AI Risk Stratification ───────────────────────────────
    GoRoute(
      path: '/risk',
      name: 'risk',
      builder: (context, state) => const RiskDashboardScreen(),
    ),

    // ── Offline Knowledge Capsule ────────────────────────────
    GoRoute(
      path: '/knowledge',
      name: 'knowledge',
      builder: (context, state) => const KnowledgeScreen(),
    ),

    // ── Secure Device Provisioning ───────────────────────────
    GoRoute(
      path: '/provisioning',
      name: 'provisioning',
      builder: (context, state) => const ProvisioningScreen(),
    ),

    // ── Data Privacy (DPDP) ──────────────────────────────────
    GoRoute(
      path: '/privacy',
      name: 'privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),

    // ── District Health Intelligence ─────────────────────────
    GoRoute(
      path: '/district',
      name: 'district',
      builder: (context, state) => const DistrictDashboardScreen(),
    ),

    // ── Health Scheme Eligibility Checker ─────────────────────
    GoRoute(
      path: '/schemes',
      name: 'schemes',
      builder: (context, state) => const SchemeEligibilityScreen(),
    ),

    // ── Showcase Projects ────────────────────────────────────
    GoRoute(
      path: '/gesture-talk',
      name: 'gestureTalk',
      builder: (context, state) => const GestureTalkScreen(),
    ),
    GoRoute(
      path: '/smart-triage',
      name: 'smartTriage',
      builder: (context, state) => const SmartTriageScreen(),
    ),
  ],

  // ── Error page ─────────────────────────────────────────────
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Not Found')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Page not found: ${state.uri}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/db/database_helper.dart';
import 'core/db/sync_engine.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/data_minimization.dart';
import 'core/services/device_provisioning.dart';
import 'core/services/district_health_intelligence.dart';
import 'core/services/model_governance.dart';
import 'core/services/resilience_manager.dart';
import 'core/services/risk_stratification.dart';
import 'core/utils/logger.dart';

/// Entry point for the SAHA application.
///
/// Initialises all core services (database, connectivity, sync engine)
/// before mounting the widget tree. All services are designed to work
/// fully offline — no internet required for any initialisation step.
void main() async {
  // Guard against Flutter web _RenderTheater assertion during initial
  // browser focus event (known Flutter 3.41.x debug-mode issue).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Also catch via FlutterError handler
    final defaultHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (kIsWeb &&
          details.toString().contains('was not laid out')) {
        Log.w('Suppressed web layout assertion (startup focus)',
            tag: 'Main');
        return;
      }
      defaultHandler?.call(details);
    };

    // Lock to portrait for small-screen FHW devices (skip on web)
    if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  Log.i('Initialising SAHA…', tag: 'Main');

  try {
    // 1. Database — in-memory (web) or SQLCipher (mobile)
    await DatabaseHelper.instance.database;
    Log.i('Database ready', tag: 'Main');

    // 2. Connectivity monitoring
    await ConnectivityService.instance.init();
    Log.i('Connectivity service ready', tag: 'Main');

    // 3. Sync engine — will auto-sync when online
    await SyncEngine.instance.init();
    Log.i('Sync engine ready', tag: 'Main');

    // 4. Enterprise services
    await ModelGovernance.instance.initialize();
    Log.i('Model governance ready', tag: 'Main');

    await RiskStratificationEngine.instance.initialize();
    Log.i('Risk stratification ready', tag: 'Main');

    await DeviceProvisioning.instance.initialize();
    Log.i('Device provisioning ready', tag: 'Main');

    await DataMinimizationEngine.instance.initialize();
    Log.i('Data minimization engine ready', tag: 'Main');

    // 8. Resilience Manager — device health monitoring
    await ResilienceManager.instance.initialize();
    Log.i('Resilience manager ready', tag: 'Main');

    // 9. District Health Intelligence
    await DistrictHealthIntelligence.instance.initialize();
    Log.i('District health intelligence ready', tag: 'Main');

    Log.i('SAHA initialisation complete ✓', tag: 'Main');
  } catch (e, st) {
    Log.e('Initialisation error (non-fatal)', tag: 'Main', error: e, stackTrace: st);
  }

  runApp(const SahaApp());
  }, (error, stack) {
    // Silently ignore the RenderBox layout assertion on web startup
    if (kIsWeb && error.toString().contains('was not laid out')) {
      return;
    }
    Log.e('Uncaught error', tag: 'Main', error: error, stackTrace: stack);
  });
}

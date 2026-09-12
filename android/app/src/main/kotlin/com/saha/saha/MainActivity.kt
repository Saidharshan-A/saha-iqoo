package com.saha.saha

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.nfcmanager.NfcManagerPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Flutter's generated registrant can omit older plugins after an
        // incremental dependency update. Register NFC defensively so the
        // patient-card flow is always available on the hackathon device.
        if (!flutterEngine.plugins.has(NfcManagerPlugin::class.java)) {
            flutterEngine.plugins.add(NfcManagerPlugin())
        }
    }
}

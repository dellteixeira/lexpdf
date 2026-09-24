import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native crash gate is isolated from Flutter and breaks restart loops', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gate = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/CrashGateActivity.kt',
    ).readAsStringSync();
    final app = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/LexPdfApplication.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".CrashGateActivity"'));
    expect(manifest, contains('android:process=":crashguard"'));
    expect(manifest, contains('android:theme="@style/CrashGateTheme"'));
    expect(manifest, contains('<action android:name="android.intent.action.MAIN"/>'));
    expect(manifest, contains('<category android:name="android.intent.category.LAUNCHER"/>'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:exported="false"'));

    expect(gate, contains('PdfCrashDiagnostics.recentExitReport(this)'));
    expect(gate, contains('PdfCrashDiagnostics.markAppLaunchAttempt(this)'));
    expect(gate, contains('LexPDF interrompeu uma falha contínua'));
    expect(gate, contains('Copiar diagnóstico'));
    expect(gate, contains('Tentar uma vez'));
    expect(gate, contains('mainWasForeground'));
    expect(gate, contains('handler.postDelayed'));
    expect(gate, isNot(contains('finish()\n        startActivity')));
    expect(gate, contains('Intent(this, MainActivity::class.java)'));

    expect(app, contains('PdfCrashDiagnostics.installUncaughtExceptionCapture(this)'));
  });

  test('startup crashes are correlated even when no PDF was opened', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();

    expect(diagnostics, contains('APP_LAUNCH_FILE'));
    expect(diagnostics, contains('markAppLaunchAttempt'));
    expect(diagnostics, contains('readAppLaunchTimestamp'));
    expect(diagnostics, contains('info.processName == packageName'));
    expect(diagnostics, contains('LAUNCH_CORRELATION_WINDOW_MS = 120_000L'));
  });

  test('crash capture survives Java crash and Android process death', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();

    expect(diagnostics, contains('Thread.setDefaultUncaughtExceptionHandler'));
    expect(diagnostics, contains('getHistoricalProcessExitReasons'));
    expect(diagnostics, contains('REASON_CRASH_NATIVE'));
    expect(diagnostics, contains('REASON_CRASH'));
    expect(diagnostics, contains('REASON_ANR'));
    expect(diagnostics, contains('REASON_LOW_MEMORY'));
    expect(diagnostics, contains('error.printStackTrace'));
    expect(diagnostics, contains('LAST_SHOWN_CAPTURE'));
    expect(diagnostics, contains('GUARD_CRASH_FILE'));
  });
}

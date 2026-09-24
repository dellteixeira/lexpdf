import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Android launch enters a framework-only crash gate before Flutter', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gate = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/CrashGateActivity.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final styles =
        File('android/app/src/main/res/values/styles.xml').readAsStringSync();

    expect(manifest, contains('android:name=".CrashGateActivity"'));
    expect(manifest, contains('android:theme="@style/CrashGateTheme"'));
    expect(manifest, contains('<action android:name="android.intent.action.MAIN"/>'));
    expect(manifest, contains('<category android:name="android.intent.category.LAUNCHER"/>'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:exported="false"'));

    // The process bootstrap must not depend on a custom Application or AppCompat.
    expect(manifest, isNot(contains('android:name=".LexPdfApplication"')));
    expect(gate, contains('class CrashGateActivity : Activity()'));
    expect(gate, isNot(contains('AppCompatActivity')));
    expect(styles, contains('parent="@android:style/Theme.Material.Light.NoActionBar"'));

    expect(gate, contains('PdfCrashDiagnostics.installUncaughtExceptionCapture(this)'));
    expect(gate, contains('PdfCrashDiagnostics.recentExitReport(this)'));
    expect(gate, contains('PdfCrashDiagnostics.markMainLaunchAttempt(this)'));
    expect(gate, contains('Diagnóstico de falha do LexPDF'));
    expect(gate, contains('Copiar diagnóstico'));
    expect(gate, contains('Continuar para o LexPDF'));
    expect(gate, contains('Intent(this, MainActivity::class.java)'));

    expect(mainActivity, contains('override fun onFlutterUiDisplayed()'));
    expect(mainActivity, contains('PdfCrashDiagnostics.markMainUiReady(this)'));
  });

  test('startup crash capture cannot silently filter main-process failures', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();

    expect(diagnostics, contains('main_startup_attempt.txt'));
    expect(diagnostics, contains('MAIN_EXIT_FRESHNESS_MS'));
    expect(diagnostics, contains('processo principal / inicialização'));
    expect(diagnostics, contains('inicialização incompleta'));
    expect(diagnostics, contains('Thread.setDefaultUncaughtExceptionHandler'));
    expect(diagnostics, contains('getHistoricalProcessExitReasons'));
    expect(diagnostics, contains('REASON_CRASH_NATIVE'));
    expect(diagnostics, contains('REASON_CRASH'));
    expect(diagnostics, contains('REASON_ANR'));
    expect(diagnostics, contains('REASON_LOW_MEMORY'));
    expect(diagnostics, contains('error.printStackTrace'));
    expect(diagnostics, contains('LAST_SHOWN_CAPTURE'));
  });
}

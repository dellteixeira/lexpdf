import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Android app launch enters native crash gate before Flutter', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gate = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/CrashGateActivity.kt',
    ).readAsStringSync();
    final app = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/LexPdfApplication.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".CrashGateActivity"'));
    expect(manifest, contains('android:theme="@style/CrashGateTheme"'));
    expect(manifest, contains('<action android:name="android.intent.action.MAIN"/>'));
    expect(manifest, contains('<category android:name="android.intent.category.LAUNCHER"/>'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:exported="false"'));

    expect(gate, contains('PdfCrashDiagnostics.recentExitReport(this)'));
    expect(gate, contains('Diagnóstico de falha do LexPDF'));
    expect(gate, contains('Copiar diagnóstico'));
    expect(gate, contains('Continuar para o LexPDF'));
    expect(gate, contains('Intent(this, MainActivity::class.java)'));

    expect(app, contains('PdfCrashDiagnostics.installUncaughtExceptionCapture(this)'));
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
  });
}

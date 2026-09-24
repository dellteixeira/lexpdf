import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF crash diagnostics attributes failures to the correct process', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(diagnostics, contains('getHistoricalProcessExitReasons'));
    expect(diagnostics, contains('info.processName == readerProcessName'));
    expect(diagnostics, contains('info.processName == packageName'));
    expect(diagnostics, contains('READER_CORRELATION_WINDOW_MS'));
    expect(diagnostics, contains('REASON_CRASH_NATIVE'));
    expect(diagnostics, contains('REASON_CRASH'));
    expect(diagnostics, contains('setProcessStateSummary'));
    expect(diagnostics, contains('UncaughtExceptionHandler'));
    expect(diagnostics, contains('error.printStackTrace'));
    expect(diagnostics, contains('uncaught_pdfreader.txt'));
    expect(diagnostics, contains('uncaught_main.txt'));

    expect(
      mainActivity,
      contains('PdfCrashDiagnostics.markReaderLaunchAttempt('),
    );
    expect(
      mainActivity,
      contains('PdfCrashDiagnostics.recordControlledLaunchFailure('),
    );
    expect(mainActivity, contains('native_reader_launch_failed'));
    expect(manifest, isNot(contains('android:name=".LexPdfApplication"')));
    expect(mainActivity, contains('PdfCrashDiagnostics.markMainUiReady(this)'));
  });

  test('PDF.js lifecycle breadcrumbs survive reader process death', () {
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(reader, contains('JS03_BEFORE_LOAD_VIEWER'));
    expect(reader, contains('JS04_VIEWER_HTML_FINISHED'));
    expect(reader, contains('JS05_DOCUMENT_READY'));
    expect(reader, contains('JS06_PAGE_VISIBLE'));
    expect(reader, contains('JSR_NATIVE_RANGE'));
  });
}

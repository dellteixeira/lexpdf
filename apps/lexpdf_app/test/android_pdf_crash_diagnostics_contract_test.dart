import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF.js crash diagnostics records exit reason and lifecycle breadcrumbs', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(diagnostics, contains('getHistoricalProcessExitReasons'));
    expect(diagnostics, contains('REASON_CRASH_NATIVE'));
    expect(diagnostics, contains('REASON_LOW_MEMORY'));
    expect(diagnostics, contains('setProcessStateSummary'));
    expect(reader, contains('JS03_BEFORE_LOAD_VIEWER'));
    expect(reader, contains('JS04_VIEWER_HTML_FINISHED'));
    expect(reader, contains('JS05_DOCUMENT_READY'));
    expect(reader, contains('JS06_PAGE_VISIBLE'));
    expect(reader, contains('JSR_RANGE'));
  });
}

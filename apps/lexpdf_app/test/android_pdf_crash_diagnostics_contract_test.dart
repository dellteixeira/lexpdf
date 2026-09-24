import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native PDF crash diagnostics records exit reason and render breadcrumbs', () {
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
    expect(reader, contains('R02_BEFORE_OPEN_PAGE'));
    expect(reader, contains('R05_BEFORE_PAGE_RENDER'));
    expect(reader, contains('R06_AFTER_PAGE_RENDER'));
    expect(reader, contains('R08_PAGE_VISIBLE'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows installer workflow emits and smoke-tests LexPDF-Setup.exe', () {
    final workflow = File(
      '../../.github/workflows/windows-desktop-integration.yml',
    ).readAsStringSync();

    expect(workflow, contains('LexPDF-Setup.exe'));
    expect(workflow, contains('ISCC.exe'));
    expect(workflow, contains('/VERYSILENT'));
    expect(workflow, contains('LexPDF.PDF'));
    expect(workflow, contains('actions/upload-artifact@v4'));
  });
}

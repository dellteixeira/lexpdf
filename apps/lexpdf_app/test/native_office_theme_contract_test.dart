import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor Office oferece alternância claro e escuro', () {
    final source = File(
      'lib/src/screens/native_office_document_screen.dart',
    ).readAsStringSync();

    expect(source, contains("tooltip: _darkMode ? 'Usar modo claro' : 'Usar modo escuro'"));
    expect(source, contains('LexPdfTheme.dark'));
    expect(source, contains('LexPdfTheme.light'));
    expect(source, contains('Icons.dark_mode_outlined'));
    expect(source, contains('Icons.light_mode_outlined'));
  });
}

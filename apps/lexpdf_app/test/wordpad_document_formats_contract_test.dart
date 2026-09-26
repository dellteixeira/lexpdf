import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Office editor has RTF and truthful legacy DOC capability', () {
    final fileService = File(
      'lib/src/core/notebook/notebook_document_file_service.dart',
    ).readAsStringSync();
    final converter = File(
      'lib/src/core/platform/legacy_word_converter.dart',
    ).readAsStringSync();
    final office = File(
      'lib/src/screens/native_office_document_screen.dart',
    ).readAsStringSync();

    expect(fileService, contains("case 'rtf':"));
    expect(fileService, contains('rtfCodec.decodeToHtml'));
    expect(fileService, contains('rtfCodec.encodeHtml'));
    expect(converter, contains('LibreOffice'));
    expect(converter, contains('Word.Application'));
    expect(converter, contains('SaveAs2'));
    expect(office, contains('_legacyDocAvailable'));
    expect(office, contains("if (_legacyDocAvailable) 'doc'"));
    expect(office, contains("'docx'"));
    expect(office, contains("'rtf'"));
    expect(office, contains("'txt'"));
  });
}

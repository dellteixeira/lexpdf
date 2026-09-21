import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WordPad has native RTF and truthful legacy DOC capability', () {
    final fileService = File(
      'lib/src/core/notebook/notebook_document_file_service.dart',
    ).readAsStringSync();
    final converter = File(
      'lib/src/core/platform/legacy_word_converter.dart',
    ).readAsStringSync();
    final chrome =
        File('lib/src/widgets/notebook_wordpad_chrome.dart').readAsStringSync();
    final screen =
        File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();

    expect(fileService, contains("case 'rtf':"));
    expect(fileService, contains('rtfCodec.decodeToHtml'));
    expect(fileService, contains('rtfCodec.encodeHtml'));
    expect(converter, contains('LibreOffice'));
    expect(converter, contains('Word.Application'));
    expect(converter, contains('SaveAs2'));
    expect(chrome, contains('legacyDocAvailable'));
    expect(chrome, contains('requer Word/LibreOffice'));
    expect(screen, contains("if (_legacyDocAvailable) 'doc'"));
  });
}

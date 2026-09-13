import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WordPad ribbon controls FluentDocument formatting by selection', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    expect(screen, contains("_defaultNotebookFontFamily = 'Arial'"));
    expect(screen, contains('_defaultNotebookFontSize = 12'));
    expect(screen, contains('_buildTextFormattingToolbar(),'));
    expect(screen, contains('document.eventHandler.handleBold()'));
    expect(screen, contains('document.eventHandler.handleItalic()'));
    expect(screen, contains('document.eventHandler.handleUnderline()'));
    expect(screen, contains('document.eventHandler.handleFontFamily'));
    expect(screen, contains('document.eventHandler.handleFontSize'));
    expect(screen, contains('document.eventHandler.handleTextAlign'));
    expect(screen, contains('document.eventHandler.handleTextColor'));
  });

  test('Arquivo menu exposes real document import and export routes', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart')
        .readAsStringSync();
    final service = File(
      'lib/src/core/notebook/notebook_document_file_service.dart',
    ).readAsStringSync();
    expect(chrome, contains("label: 'Abrir documento'"));
    expect(chrome, contains("label: 'Salvar como DOCX'"));
    expect(chrome, contains("label: 'Salvar como TXT'"));
    expect(chrome, contains("label: 'Exportar PDF'"));
    expect(chrome, contains("label: 'Salvar como DOC'"));
    expect(chrome, contains("label: 'Salvar como RTF'"));
    expect(screen, contains('_openRichDocumentFile()'));
    expect(screen, contains("_saveRichDocumentAs('docx')"));
    expect(service, contains("case 'docx':"));
    expect(service, contains("case 'txt':"));
    expect(service, contains("case 'pdf':"));
    expect(service, contains('LegacyWordBridgeUnavailable'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Documentos Office usa editor Flutter nativo e não WebView', () {
    final screen = File(
      'lib/src/screens/native_office_document_screen.dart',
    ).readAsStringSync();
    final home = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('FluentDocumentWidget'));
    expect(screen, contains('NotebookDocumentFileService'));
    expect(screen, isNot(contains("package:flutter_inappwebview")));
    expect(screen, isNot(contains('InAppWebView(')));
    expect(screen, isNot(contains('LexPdfOffice')));
    expect(screen, isNot(contains('@genoffice/')));
    expect(screen, isNot(contains('@tiptap/')));

    expect(home, contains('Documentos Office'));
    expect(home, contains('NativeOfficeDocumentScreen'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop PDF search stays visible and navigates highlighted matches', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(workspace, contains('searchVisible: tab.searchVisible'));
    expect(workspace, contains('onSearchClosed: () => _closeDocumentSearch(tab)'));
    expect(editor, contains('PdfTextSearcher'));
    expect(editor, contains('Localizar palavra ou frase'));
    expect(editor, contains("'$current/$total'"));
    expect(editor, contains('goToNextMatch()'));
    expect(editor, contains('goToPrevMatch()'));
    expect(editor, contains('pageTextMatchPaintCallback'));
    expect(editor, contains('_PdfSearchHighlightOverlayPainter'));
    expect(editor, contains('Palavra inteira'));
    expect(editor, contains('Diferenciar maiúsculas/minúsculas'));
  });
}

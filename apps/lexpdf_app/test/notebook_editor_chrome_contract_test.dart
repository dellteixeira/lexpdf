import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor chrome is extracted into the WordPad shell', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart')
        .readAsStringSync();

    expect(screen, contains("import '../widgets/notebook_wordpad_chrome.dart';"));
    expect(screen, contains('NotebookWordPadScaffold('));
    expect(screen, contains('homeRibbon: _buildTextFormattingToolbar()'));
    expect(screen, contains('drawingRibbon: _buildToolbar()'));
    expect(screen, contains('viewRibbon: _buildViewRibbon()'));

    expect(chrome, contains('class NotebookWordPadScaffold'));
    expect(chrome, contains('class NotebookWordPadStatusBar'));
    expect(chrome, contains('class NotebookDocumentRuler'));
    expect(chrome, contains('height: 96'));
    expect(chrome, contains('height: 29'));
  });

  test('extracted notebook chrome preserves user-facing controls', () {
    final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')
        .readAsStringSync();

    expect(chrome, contains("tooltip: 'Página anterior'"));
    expect(chrome, contains("tooltip: 'Próxima página'"));
    expect(chrome, contains("tooltip: 'Adicionar página'"));
    expect(chrome, contains("tooltip: 'Duplicar página'"));
    expect(chrome, contains("tooltip: 'Excluir página'"));
    expect(chrome, contains("tooltip: 'Diminuir zoom'"));
    expect(chrome, contains("tooltip: 'Aumentar zoom'"));
    expect(chrome, contains("tooltip: 'Ajustar página'"));
    expect(chrome, contains('layer.name'));
    expect(chrome, contains('Icons.visibility_off_outlined'));
    expect(chrome, contains('Icons.lock_outline'));
    expect(chrome, contains("Text(\n                '\$layerCount'"));
  });
}

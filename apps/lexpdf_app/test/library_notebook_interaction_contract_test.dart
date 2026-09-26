import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library documents open directly in the unified PDF workspace', () {
    final library = File('lib/src/screens/library_screen.dart')
        .readAsStringSync();
    final documentRef = File('lib/src/core/documents/document_provider.dart')
        .readAsStringSync();

    expect(library, contains('Documentos da biblioteca'));
    expect(library, contains("'Clique para abrir em Trabalhar com PDF'"));
    expect(library, contains('final canOpen = _hasLocalPath(document);'));
    expect(
      library,
      contains(
        'onTap: canOpen ? () => _openWorkspaceDocument(document) : null',
      ),
    );
    expect(library, contains('builder: (_) => PdfWorkspaceScreen('));
    expect(
      documentRef,
      contains('provider == DocumentProviderKind.local ? id : null'),
    );
  });

  test('notebooks use the new stylus-first shelf and editor', () {
    final shelf = File('lib/src/screens/notebook_screen.dart').readAsStringSync();
    final editor = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();

    expect(shelf, contains('NotebookCoverCard('));
    expect(shelf, contains('Novo caderno'));
    expect(shelf, contains('firstPageFormat: result.format'));
    expect(shelf, contains('firstPageBackground: result.background'));
    expect(shelf, contains('StylusNotebookEditorScreen('));

    expect(editor, contains('InkCanvas('));
    expect(editor, contains('stylusOnly: _stylusOnly'));
    expect(editor, contains('eraserMode: _eraserMode'));
    expect(editor, contains('lassoMode: _lassoMode'));
    expect(editor, contains("label: 'Caneta'"));
    expect(editor, contains("label: 'Marca'"));
    expect(editor, contains("label: 'Borracha'"));
    expect(editor, contains("label: 'Laço'"));
    expect(editor, contains('InkPageFormat.a4Portrait'));
    expect(editor, contains('InkPageFormat.a3Portrait'));
    expect(editor, contains('InkPageFormat.infinite'));
  });

  test('notebook paper gallery includes study and technical templates', () {
    final models = File('lib/src/core/ink/ink_models.dart').readAsStringSync();
    final background = File(
      'lib/src/widgets/notebook_page_background.dart',
    ).readAsStringSync();

    expect(models, contains('cornell'));
    expect(models, contains('planner'));
    expect(models, contains('crossGrid'));
    expect(models, contains('isometric'));
    expect(models, contains('engineering'));
    expect(models, contains('music'));
    expect(models, contains('taskList'));

    expect(background, contains('InkPageBackground.cornell'));
    expect(background, contains('InkPageBackground.engineering'));
    expect(background, contains('InkPageBackground.music'));
  });

  test('legacy WordPad notebook UI is removed', () {
    expect(File('lib/src/screens/layered_notebook_screen.dart').existsSync(),
        isFalse);
    expect(File('lib/src/widgets/notebook_wordpad_chrome.dart').existsSync(),
        isFalse);
    expect(File('lib/src/widgets/notebook_editor_toolbar.dart').existsSync(),
        isFalse);
  });
}

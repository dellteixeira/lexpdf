import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cadernos usa o novo fluxo stylus-first', () {
    final hub = File(
      'lib/src/screens/notebook_screen.dart',
    ).readAsStringSync();
    final editor = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();
    final paper = File(
      'lib/src/core/notebook/notebook_paper.dart',
    ).readAsStringSync();
    final canvas = File(
      'lib/src/widgets/ink_canvas.dart',
    ).readAsStringSync();
    final home = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();
    final database = File(
      'lib/src/core/storage/local_database.dart',
    ).readAsStringSync();

    expect(hub, contains('StylusNotebookEditorScreen'));
    expect(hub, contains('Novo caderno'));
    expect(hub, contains('Cornell'));
    expect(hub, contains('Partitura'));

    expect(paper, contains('NotebookPaperSize.a4'));
    expect(paper, contains('NotebookPaperSize.a3'));
    expect(paper, contains('NotebookPaperSize.infinite'));

    expect(editor, contains('InkCanvas'));
    expect(editor, contains('_NotebookTool.eraser'));
    expect(editor, contains('_NotebookTool.lasso'));
    expect(editor, contains('_NotebookTool.hand'));
    expect(editor, isNot(contains('_NotebookTool.pencil')));
    expect(editor, contains('InkBrush.values'));
    expect(editor, contains('Tamanho do brush'));
    expect(editor, contains('Configurar caneta: brush, cor, tamanho e opacidade'));
    expect(editor, contains('IconButton.filledTonal'));
    expect(editor, isNot(contains('Icon(Icons.tune, color: color)')));
    expect(editor, contains('0xFF00ACC1'));
    expect(editor, contains('_deleteSelection'));
    expect(editor, contains('_rememberUpdatedStroke'));
    expect(editor, contains('onDeleteSelection'));
    expect(editor, contains('strokeOpacity: _activeOpacity'));
    expect(editor, contains('reorderPages'));
    expect(editor, contains('Somente caneta/stylus escreve'));

    expect(canvas, contains('_SelectionGesture.move'));
    expect(canvas, contains('_SelectionGesture.resize'));
    expect(canvas, contains('moveSelected(delta.dx, delta.dy)'));
    expect(canvas, contains('scaleSelected(factor.toDouble())'));
    expect(canvas, contains('strokeOpacity'));

    expect(
      database,
      contains("    }\n\n    if (version < 12)"),
      reason: 'A migração do brush deve rodar também para bancos já na versão 11.',
    );

    expect(home, contains('section == _HomeSection.notebooks'));
    expect(home, isNot(contains('LayeredNotebookScreen')));
    expect(File('lib/src/screens/layered_notebook_screen.dart').existsSync(), isFalse);
  });
}

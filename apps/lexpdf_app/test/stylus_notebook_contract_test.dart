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
    final home = File(
      'lib/src/screens/library_workspace_home_screen.dart',
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
    expect(editor, contains('reorderPages'));
    expect(editor, contains('Somente caneta/stylus escreve'));

    expect(home, contains('section == _HomeSection.notebooks'));
    expect(home, isNot(contains('LayeredNotebookScreen')));
    expect(File('lib/src/screens/layered_notebook_screen.dart').existsSync(), isFalse);
  });
}

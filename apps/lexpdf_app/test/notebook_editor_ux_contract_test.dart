import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor exposes zoom, selection, hand, text and bounded toolbar', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart')
        .readAsStringSync();
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final inkControls = File('lib/src/widgets/notebook_ink_controls.dart')
        .readAsStringSync();
    final objectControls = File('lib/src/widgets/notebook_object_controls.dart')
        .readAsStringSync();

    expect(screen, contains('TransformationController'));
    expect(screen, contains('NotebookWordPadScaffold('));
    expect(screen, contains('NotebookEditorToolbar('));
    expect(screen, contains('_buildTextFormattingToolbar()'));
    expect(chrome, contains("label: 'Mais'"));
    expect(chrome, contains("label: 'Menos'"));
    expect(chrome, contains("tooltip: 'Ajustar à página'"));
    expect(chrome, contains('onZoomChanged'));
    expect(chrome, contains('NotebookWordPadViewRibbon'));
    expect(toolbar, contains('NotebookInkControls('));
    expect(inkControls, contains("label: 'Selecionar'"));
    expect(inkControls, contains("label: 'Mão'"));
    expect(toolbar, contains('NotebookObjectControls('));
    expect(objectControls, contains("label: 'Texto'"));
    expect(toolbar, contains('WordPadRibbonGroup('));
    expect(toolbar, contains('SingleChildScrollView('));
    expect(toolbar, contains('scrollDirection: Axis.horizontal'));
    expect(toolbar, isNot(contains('thumbVisibility: true')));
    expect(toolbar, isNot(contains('trackVisibility: true')));

    // Selection remains exclusive with Hand navigation. Text editing uses the
    // same object layer and therefore keeps these ownership rules intact.
    expect(screen, contains('_pointerMode && !_handMode && _canEditActiveLayer'));
    expect(screen, contains('ignoring:'));
    expect(screen, contains('!_canEditActiveLayer || _pointerMode || _handMode'));
    expect(screen, contains('panEnabled: _handMode'));
    expect(screen, contains('scaleEnabled: _handMode'));
  });
}

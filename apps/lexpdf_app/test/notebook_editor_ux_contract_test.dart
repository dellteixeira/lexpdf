import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor exposes zoom, selection, hand, text and bounded toolbar', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')
        .readAsStringSync();
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final inkControls = File('lib/src/widgets/notebook_ink_controls.dart')
        .readAsStringSync();
    final objectControls = File('lib/src/widgets/notebook_object_controls.dart')
        .readAsStringSync();

    expect(screen, contains('TransformationController'));
    expect(screen, contains('NotebookZoomControls('));
    expect(screen, contains('NotebookEditorToolbar('));
    expect(chrome, contains("tooltip: 'Aumentar zoom'"));
    expect(chrome, contains("tooltip: 'Diminuir zoom'"));
    expect(chrome, contains("tooltip: 'Ajustar página'"));
    expect(chrome, contains('onZoomSelected'));
    expect(chrome, contains('onCustomZoom'));
    expect(toolbar, contains('NotebookInkControls('));
    expect(inkControls, contains("label: const Text('Selecionar')"));
    expect(inkControls, contains("label: const Text('Mão')"));
    expect(toolbar, contains('NotebookObjectControls('));
    expect(objectControls, contains("label: const Text('Texto')"));
    expect(toolbar, contains('height: 54'));
    expect(toolbar, contains('SingleChildScrollView('));
    expect(toolbar, contains('scrollDirection: Axis.horizontal'));
    expect(toolbar, isNot(contains('thumbVisibility: true')));
    expect(toolbar, isNot(contains('trackVisibility: true')));

    // Selection is reserved for editable objects and is explicitly disabled
    // while Hand mode owns page panning. These checks intentionally validate
    // behavior tokens instead of depending on one-line source formatting.
    expect(screen, contains('enabled: _pointerMode &&'));
    expect(screen, contains('!_handMode &&'));
    expect(screen, contains('_canEditActiveLayer,'));
    expect(screen, contains('ignoring: !_canEditActiveLayer ||'));
    expect(screen, contains('_pointerMode ||'));
    expect(screen, contains('_handMode,'));
    expect(screen, contains('panEnabled: _handMode'));
    expect(screen, contains('scaleEnabled: _handMode'));
  });
}

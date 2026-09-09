import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook object controls are extracted from the toolbar', () {
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final controls = File('lib/src/widgets/notebook_object_controls.dart')
        .readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();

    expect(toolbar, contains("import 'notebook_object_controls.dart';"));
    expect(toolbar, contains('NotebookObjectControls('));
    expect(toolbar, contains('onPointerModeChanged(true)'));
    expect(controls, contains('class NotebookObjectControls'));
    expect(controls, contains("label: const Text('Texto')"));
    expect(controls, contains("tooltip: 'Inserir forma e selecionar'"));
    expect(controls, contains("tooltip: 'Inserir imagem e selecionar'"));
    expect(controls, contains("tooltip: 'Editar texto selecionado'"));
    expect(controls, contains("label: const Text('Excluir')"));
    expect(objectLayer, contains('enum _ResizeHandle'));
    expect(objectLayer, contains('_ResizeHandle.topLeft'));
    expect(objectLayer, contains('_ResizeHandle.topRight'));
    expect(objectLayer, contains('_ResizeHandle.bottomLeft'));
    expect(objectLayer, contains('_ResizeHandle.bottomRight'));
    expect(objectLayer, contains('canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke)'));
  });
}

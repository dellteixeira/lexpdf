import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook object controls are extracted from the toolbar', () {
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final controls = File('lib/src/widgets/notebook_object_controls.dart')
        .readAsStringSync();

    expect(toolbar, contains("import 'notebook_object_controls.dart';"));
    expect(toolbar, contains('NotebookObjectControls('));
    expect(controls, contains('class NotebookObjectControls'));
    expect(controls, contains("label: const Text('Texto')"));
    expect(controls, contains("tooltip: 'Inserir forma'"));
    expect(controls, contains("tooltip: 'Inserir imagem'"));
    expect(controls, contains("tooltip: 'Editar texto'"));
    expect(controls, contains("tooltip: 'Excluir objeto'"));
  });
}

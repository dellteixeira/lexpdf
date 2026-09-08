import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook toolbar composes extracted ink controls', () {
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final controls = File('lib/src/widgets/notebook_ink_controls.dart')
        .readAsStringSync();

    expect(toolbar, contains("import 'notebook_ink_controls.dart';"));
    expect(toolbar, contains('NotebookInkControls('));
    expect(controls, contains("label: const Text('Selecionar')"));
    expect(controls, contains("label: Text('Caneta')"));
    expect(controls, contains("label: Text('Lápis')"));
    expect(controls, contains("label: Text('Marca-texto')"));
    expect(controls, contains("label: const Text('Borracha')"));
    expect(controls, contains("? 'Laço (\$selectionCount)' : 'Laço'"));
  });
}

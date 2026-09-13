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
    expect(controls, contains("label: 'Selecionar'"));
    expect(controls, contains("label: 'Caneta'"));
    expect(controls, contains("label: 'Lápis'"));
    expect(controls, contains("label: 'Marca-texto'"));
    expect(controls, contains("label: 'Borracha'"));
    expect(controls, contains("label: selectionCount > 0 ? 'Laço \$selectionCount' : 'Laço'"));
  });
}

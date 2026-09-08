import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor chrome is extracted from the screen state', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')
        .readAsStringSync();

    expect(screen, contains("import '../widgets/notebook_editor_chrome.dart';"));
    expect(screen, contains('NotebookNavigationBar('));
    expect(screen, contains('NotebookLayerStatus('));
    expect(screen, contains('NotebookZoomControls('));

    expect(chrome, contains('class NotebookNavigationBar'));
    expect(chrome, contains('class NotebookLayerStatus'));
    expect(chrome, contains('class NotebookZoomControls'));
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
    expect(chrome, contains("Text('Camada ativa: \${layer.name}')"));
  });
}

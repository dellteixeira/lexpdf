import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor exposes zoom, pointer, text and bounded toolbar', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')
        .readAsStringSync();

    expect(screen, contains('TransformationController'));
    expect(screen, contains('NotebookZoomControls('));
    expect(chrome, contains("tooltip: 'Aumentar zoom'"));
    expect(chrome, contains("tooltip: 'Diminuir zoom'"));
    expect(chrome, contains("tooltip: 'Ajustar página'"));
    expect(screen, contains("label: const Text('Selecionar')"));
    expect(screen, contains("label: const Text('Texto')"));
    expect(screen, contains('thumbVisibility: true'));
    expect(screen, contains('trackVisibility: true'));
    expect(screen, contains('scrollbarOrientation: ScrollbarOrientation.bottom'));
    expect(screen, contains('enabled: _pointerMode && _canEditActiveLayer'));
    expect(screen, contains('ignoring: !_canEditActiveLayer || _pointerMode'));
  });
}

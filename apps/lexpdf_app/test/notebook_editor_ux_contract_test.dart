import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook editor exposes zoom, pointer, text and bounded toolbar', () {
    final source = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();

    expect(source, contains('TransformationController'));
    expect(source, contains("tooltip: 'Aumentar zoom'"));
    expect(source, contains("tooltip: 'Diminuir zoom'"));
    expect(source, contains("tooltip: 'Ajustar página'"));
    expect(source, contains("label: const Text('Selecionar')"));
    expect(source, contains("label: const Text('Texto')"));
    expect(source, contains('thumbVisibility: true'));
    expect(source, contains('trackVisibility: true'));
    expect(source, contains('scrollbarOrientation: ScrollbarOrientation.bottom'));
    expect(source, contains('enabled: _pointerMode && _canEditActiveLayer'));
    expect(source, contains('ignoring: !_canEditActiveLayer || _pointerMode'));
  });
}

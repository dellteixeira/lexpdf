import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook text tool uses Flutter text input and returns to pointer mode', () {
    final source = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();

    expect(source, contains("title: const Text('Inserir texto')"));
    expect(source, contains('TextField('));
    expect(source, contains('autofocus: true'));
    expect(source, contains('_pointerMode = true'));
  });
}

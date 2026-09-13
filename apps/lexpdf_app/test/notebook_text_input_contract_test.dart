import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook text tool edits directly on the page with Flutter text input', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();

    expect(screen, contains('_editingTextObjectId = object.id'));
    expect(screen, contains('_pointerMode = true'));
    expect(screen, contains('_buildTextFormattingToolbar()'));
    expect(screen, isNot(contains("title: const Text('Inserir texto')")));

    expect(objectLayer, contains('_InlineNotebookTextEditor'));
    expect(objectLayer, contains('TextField('));
    expect(objectLayer, contains('autofocus: true'));
    expect(objectLayer, contains('cursorColor:'));
    expect(objectLayer, contains('onChanged: (_) => _emit()'));
  });
}

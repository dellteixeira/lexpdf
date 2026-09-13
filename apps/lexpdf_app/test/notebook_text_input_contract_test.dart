import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook text input is a flowing rich document on the paper', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();
    final surface = File('lib/src/widgets/notebook_rich_document_surface.dart')
        .readAsStringSync();
    expect(screen, contains('void _activateTextMode()'));
    expect(screen, contains('document.requestEditorFocus()'));
    expect(screen, contains('NotebookRichDocumentSurface('));
    expect(screen, contains('enabled: _textMode && !_handMode'));
    expect(screen, isNot(contains('_editingTextObjectId')));
    expect(surface, contains('FluentDocumentWidget('));
    expect(surface, contains('onSurface: Color(0xFF202124)'));
    expect(objectLayer, isNot(contains('_InlineNotebookTextEditor')));
    expect(objectLayer, isNot(contains('TextField(')));
  });
}

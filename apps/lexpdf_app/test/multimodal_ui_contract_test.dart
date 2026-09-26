import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF pages retain explicit multimodal indexing after notebook rewrite', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final notebook = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();

    expect(workspace, contains('Analisar página visualmente com IA'));
    expect(workspace, contains('PdfPageVisionRasterizer'));
    expect(workspace, contains("sourceKind: 'pdf_visual'"));

    // The new notebook is intentionally handwriting-first. Legacy notebook
    // image-indexing controls must not be reintroduced as hidden dependencies.
    expect(notebook, contains('InkCanvas('));
    expect(notebook, isNot(contains('_indexNotebookImagesWithAi')));
    expect(notebook, isNot(contains('RemoteAiVisionService')));
  });
}

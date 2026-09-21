import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF pages and notebook images expose explicit multimodal indexing actions', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final notebook =
        File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final chrome =
        File('lib/src/widgets/notebook_wordpad_chrome.dart').readAsStringSync();

    expect(workspace, contains('Analisar página visualmente com IA'));
    expect(workspace, contains('PdfPageVisionRasterizer'));
    expect(workspace, contains("sourceKind: 'pdf_visual'"));
    expect(notebook, contains('_indexNotebookImagesWithAi'));
    expect(notebook, contains('onIndexImagesAi:'));
    expect(notebook, contains("sourceKind: 'notebook_visual'"));
    expect(notebook, contains('RemoteAiVisionService'));
    expect(chrome, contains('_NotebookFileAction.indexImagesAi'));
    expect(chrome, contains('Indexar imagens do caderno com IA'));
  });
}

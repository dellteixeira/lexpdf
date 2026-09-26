import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF page manager is thumbnail-first', () {
    final source = File('lib/src/screens/pdf_page_tools_screen.dart')
        .readAsStringSync();

    expect(source, contains('PdfDocumentViewBuilder.file'));
    expect(source, contains('GridView.builder'));
    expect(source, contains('PdfPageView('));
    expect(source, contains('Selecionar todas'));
    expect(source, contains('Mover uma posição para trás'));
    expect(source, isNot(contains('ReorderableListView.builder')));
  });

  test('PDF workspace exposes keyboard navigation and numeric zoom', () {
    final entrypoint = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();
    final implementation = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final source = '$entrypoint\n$implementation';

    expect(
      entrypoint,
      contains("import 'pdf_workspace_stylus_screen.dart' as editor;"),
    );
    expect(entrypoint, contains('editor.PdfWorkspaceScreen('));
    expect(source, contains('LogicalKeyboardKey.arrowLeft'));
    expect(source, contains('LogicalKeyboardKey.arrowRight'));
    expect(source, contains('LogicalKeyboardKey.arrowUp'));
    expect(source, contains('LogicalKeyboardKey.arrowDown'));
    expect(source, contains('_zoomPresets'));
    expect(source, contains('Personalizado…'));
    expect(source, contains('_controller.zoomOnLocalPosition'));
    expect(source, contains('localPosition: _effectiveZoomLocalAnchor()'));
  });

  test('Notebook separates lasso from hand navigation and supports fit/zoom', () {
    final screen = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('enum _NotebookTool'));
    expect(screen, contains('_NotebookTool.lasso'));
    expect(screen, contains('_NotebookTool.hand'));
    expect(screen, contains('TransformationController'));
    expect(screen, contains('panEnabled: _hand'));
    expect(screen, contains('scaleEnabled: true'));
    expect(screen, contains('minScale: 0.08'));
    expect(screen, contains('maxScale: 6'));
    expect(screen, contains('void _fitPage('));
    expect(screen, contains('NotebookPaperSize.infer'));
  });
}

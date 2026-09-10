import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF page manager is thumbnail-first', () {
    final source = File(
      'lib/src/screens/pdf_page_tools_screen.dart',
    ).readAsStringSync();

    expect(source, contains('PdfDocumentViewBuilder.file'));
    expect(source, contains('GridView.builder'));
    expect(source, contains('PdfPageView('));
    expect(source, contains('Selecionar todas'));
    expect(source, contains('Mover uma posição para trás'));
    expect(source, isNot(contains('ReorderableListView.builder')));
  });

  test('PDF workspace exposes keyboard navigation and numeric zoom', () {
    final entrypoint = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();
    final implementation = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final source = '$entrypoint\n$implementation';

    expect(source, contains("export 'pdf_workspace_stylus_screen.dart';"));
    expect(source, contains('LogicalKeyboardKey.arrowLeft'));
    expect(source, contains('LogicalKeyboardKey.arrowRight'));
    expect(source, contains('LogicalKeyboardKey.arrowUp'));
    expect(source, contains('LogicalKeyboardKey.arrowDown'));
    expect(source, contains('_zoomPresets'));
    expect(source, contains('Personalizado…'));
    expect(source, contains('_controller.setZoom'));
  });

  test('Notebook separates selection from hand navigation and has zoom presets', () {
    final screen = File(
      'lib/src/screens/layered_notebook_screen.dart',
    ).readAsStringSync();
    final controls = File(
      'lib/src/widgets/notebook_ink_controls.dart',
    ).readAsStringSync();
    final zoom = File(
      'lib/src/widgets/notebook_editor_chrome.dart',
    ).readAsStringSync();

    expect(screen, contains('bool _handMode = false'));
    expect(screen, contains('panEnabled: _handMode'));
    expect(screen, contains('enabled: _pointerMode &&'));
    expect(screen, contains('onHandModeChanged'));
    expect(controls, contains("label: const Text('Selecionar')"));
    expect(controls, contains("label: const Text('Mão')"));
    expect(zoom, contains('NotebookZoomControls'));
    expect(zoom, contains('onZoomSelected'));
    expect(zoom, contains('Personalizado…'));
  });
}

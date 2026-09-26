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

  test(
    'Notebook uses stylus tools with two-finger pan and zoom',
    () {
      final screen = File(
        'lib/src/screens/stylus_notebook_editor_screen.dart',
      ).readAsStringSync();
      final ink = File('lib/src/widgets/ink_canvas.dart').readAsStringSync();
      final navigation = File(
        'lib/src/widgets/notebook_two_finger_navigation_region.dart',
      ).readAsStringSync();

      expect(screen, contains('InteractiveViewer('));
      expect(screen, contains('panEnabled: false'));
      expect(screen, contains('scaleEnabled: false'));
      expect(screen, contains('InkCanvas('));
      expect(screen, contains('lassoMode: _lassoMode'));
      expect(screen, contains('eraserMode: _eraserMode'));
      expect(screen, contains('stylusOnly: _stylusOnly'));
      expect(screen, contains('_fitPage'));
      expect(ink, contains('NotebookTwoFingerNavigationRegion('));
      expect(navigation, contains('_touchPositions.length >= 2'));
      expect(navigation, contains('currentDistance / _startDistance'));
    },
  );

}

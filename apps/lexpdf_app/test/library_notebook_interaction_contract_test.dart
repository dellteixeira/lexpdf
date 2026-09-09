import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library documents open directly in the unified PDF workspace', () {
    final library = File('lib/src/screens/library_screen.dart').readAsStringSync();
    final documentRef = File('lib/src/core/documents/document_provider.dart')
        .readAsStringSync();

    expect(library, contains('Documentos da biblioteca'));
    expect(library, contains("'Clique para abrir em Trabalhar com PDF'"));
    expect(library, contains('final canOpen = _hasLocalPath(document);'));
    expect(library, contains('onTap: canOpen ? () => _openWorkspaceDocument(document) : null'));
    expect(library, contains('builder: (_) => PdfWorkspaceScreen('));
    expect(documentRef, contains('provider == DocumentProviderKind.local ? id : null'));
  });

  test('notebook select exposes direct object editing actions', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final objectControls = File('lib/src/widgets/notebook_object_controls.dart')
        .readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();
    final styleControls = File('lib/src/widgets/notebook_editor_toolbar_groups.dart')
        .readAsStringSync();

    expect(screen, contains('onScaleObjectDown:'));
    expect(screen, contains('onScaleObjectUp:'));
    expect(screen, contains('onDuplicateObject:'));
    expect(screen, contains('_setSelectedObjectWidth(value)'));
    expect(screen, contains('_setSelectedObjectColor(value)'));
    expect(screen, contains('_deleteSelectedObject()'));
    expect(screen, contains('_editTextObject(selectedObject)'));
    expect(toolbar, contains('objectSelected: selectedObject != null'));
    expect(toolbar, contains('onPointerModeChanged(true)'));
    expect(objectControls, contains("tooltip: 'Duplicar objeto selecionado'"));
    expect(objectControls, contains("label: const Text('Excluir')"));
    expect(objectLayer, contains('onTapDown: (_) => widget.onSelectionChanged(object.id)'));
    expect(objectLayer, contains('enum _ResizeHandle'));
    expect(styleControls, contains("'Espessura do objeto'"));
  });

  test('notebook inserted lines are horizontal until explicitly rotated', () {
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();

    expect(objectLayer, contains('final y = size.height / 2;'));
    expect(objectLayer, contains('canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke)'));
    expect(objectLayer, isNot(contains('canvas.drawLine(Offset.zero, Offset(size.width, size.height), stroke)')));
  });

  test('notebook numeric zoom preserves the viewport center', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();

    expect(screen, contains('final GlobalKey _pageViewportKey = GlobalKey();'));
    expect(screen, contains('_pageTransformController.toScene(viewportCenter)'));
    expect(screen, contains('Matrix4.translationValues('));
    expect(screen, contains('Matrix4.diagonal3Values(next, next, 1)'));
  });
}

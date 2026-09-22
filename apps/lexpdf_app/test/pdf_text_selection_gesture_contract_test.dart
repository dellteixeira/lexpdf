import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text selection freezes the page and owns Android touch drag', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(
      workspace,
      contains('bool get _textSelectionMode => _stylusMode == _StylusMode.selectText;'),
    );
    expect(
      workspace,
      contains('active: _android && !_textSelectionMode'),
    );
    expect(
      workspace,
      contains('!_textSelectionMode &&'),
    );
    expect(
      workspace,
      contains('enableSelectionHandles: _android ? true : null'),
    );
    expect(
      workspace,
      contains('onSelectionHandlePanStart: (_)'),
    );
    expect(
      workspace,
      contains('_controller.stopInteractiveViewerAnimation();'),
    );
  });

  test('text selection remains backed by pdfrx native selection engine', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(workspace, contains('PdfTextSelectionParams('));
    expect(workspace, contains('enabled: _textSelectionMode'));
    expect(workspace, contains('_selectionMenu.buildContextMenu'));
    expect(workspace, contains('showContextMenuAutomatically: true'));
  });
}

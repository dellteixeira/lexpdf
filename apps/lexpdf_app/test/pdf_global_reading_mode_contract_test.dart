import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded PDF removes duplicate document header and reclaims its height', () {
    final shell =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final editor =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();

    expect(shell, contains('showDocumentHeader: false'));
    expect(editor, contains('final bool showDocumentHeader;'));
    expect(
      editor,
      contains("appBar: (_readingMode || !widget.showDocumentHeader)"),
    );

    // The document name remains available in the tab/workspace shell, but the
    // embedded editor no longer consumes a second AppBar row for it.
    expect(shell, contains('tab.document.name'));
  });

  test('Ctrl+H and Android single tap share the global reading mode', () {
    final shell =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final editor =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();

    expect(shell, contains('bind(LogicalKeyboardKey.keyH, _toggleFullScreen)'));
    expect(shell, contains("if (!_fullScreen)"));
    expect(editor, contains('onSingleTap: _handleAndroidPdfTap'));
    expect(editor, contains('if (!widget.fullScreen && _stylusMode != _StylusMode.hand)'));
    expect(editor, contains('_requestFullScreen();'));
    expect(editor, contains('widget.onToggleFullScreen'));
  });
}

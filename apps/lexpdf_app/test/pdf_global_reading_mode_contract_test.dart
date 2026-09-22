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

  test('reading mode is explicit and a normal PDF tap does not hide chrome', () {
    final shell =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final editor =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final androidRouter = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();

    expect(shell, contains('bind(LogicalKeyboardKey.keyH, _toggleFullScreen)'));
    expect(shell, contains("if (!_fullScreen)"));
    expect(editor, contains('_requestFullScreen'));
    expect(editor, contains('widget.onToggleFullScreen'));
    expect(editor, isNot(contains('onSingleTap: _handleAndroidPdfTap')));
    expect(editor, isNot(contains('void _handleAndroidPdfTap()')));
    expect(androidRouter, isNot(contains('final VoidCallback? onSingleTap;')));
    expect(androidRouter, isNot(contains('widget.onSingleTap?.call();')));
  });

  test('immersive chrome transitions preserve the exact visible PDF page', () {
    final shell =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final editor =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();

    expect(editor, contains('int? _chromeTransitionPage;'));
    expect(
      editor,
      contains('final preservedPage = _controller.pageNumber ?? _page;'),
    );
    expect(editor, contains('_schedulePageRestoreAfterChromeChange'));
    expect(editor, contains('_restorePageAfterChromeChange'));
    expect(editor, contains('duration: Duration.zero'));
    expect(
      editor,
      contains('if (transitionTarget != null && pageNumber != transitionTarget)'),
    );
    expect(editor, contains('widget.onPageChanged?.call(pageNumber);'));
    expect(shell, contains('_recordVisiblePage'));
    expect(shell, contains('onPageChanged: (pageNumber) =>'));
    expect(editor, contains('if (!_readingMode && _loadingInk)'));
  });
}

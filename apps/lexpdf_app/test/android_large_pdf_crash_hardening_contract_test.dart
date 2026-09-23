import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android keeps only the active native PDF viewer mounted', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    expect(workspace, contains('Widget _buildPdfEditorSurface()'));
    expect(workspace, contains('if (Platform.isAndroid)'));
    expect(workspace, contains('return _buildEditorForTab(_tabs[_activeIndex])'));
    expect(workspace, contains('PdfDocument? viewerDocument'));
    expect(workspace, contains('onViewerDocumentChanged: (document) =>'));
  });

  test('automatic indexing never opens a competing PDF document', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final ocr =
        File('lib/src/core/ocr/mobile_pdf_ocr_service.dart').readAsStringSync();

    final inspectStart =
        workspace.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final activityStart = workspace.indexOf(
      'void _markReaderActivity',
      inspectStart,
    );
    expect(inspectStart, greaterThanOrEqualTo(0));
    expect(activityStart, greaterThan(inspectStart));

    final inspectBody = workspace.substring(inspectStart, activityStart);
    expect(inspectBody, contains('tab.viewerDocument'));
    expect(inspectBody, isNot(contains('inspectTextAvailability(')));
    expect(inspectBody, isNot(contains('PdfDocument.openFile(')));

    expect(workspace, contains('openedDocument: viewerDocument'));
    expect(
      ocr,
      contains('final document = openedDocument ?? await PdfDocument.openFile(filePath!)'),
    );
    expect(ocr, contains('if (ownsDocument)'));
  });

  test('Android reader starts with a small bounded rendering working set', () {
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final policy =
        File('lib/src/core/pdf/huge_pdf_policy.dart').readAsStringSync();
    final normalizedEditor = editor.replaceAll(RegExp(r'\s+'), ' ');

    expect(policy, contains('_mobileViewerCacheUnknownMaxBytes = 20 * 1024 * 1024'));
    expect(policy, contains('_mobileViewerCacheLargeMaxBytes = 24 * 1024 * 1024'));
    expect(policy, contains('_mobileViewerCacheHugeMaxBytes = 16 * 1024 * 1024'));
    expect(policy, contains('androidOnePassRenderingSizeThreshold = 900'));
    expect(policy, contains('androidMaxRenderLongEdge = 2200'));
    expect(policy, contains('androidCacheExtent = 0.12'));
    expect(policy, contains('backgroundIndexIdleDelay = Duration(seconds: 5)'));
    expect(policy, contains('idleIndexChunkPages = 6'));

    expect(
      normalizedEditor,
      contains('HugePdfPolicy .androidOnePassRenderingSizeThreshold'),
    );
    expect(
      normalizedEditor,
      contains('HugePdfPolicy.androidMaxRenderLongEdge'),
    );
    expect(normalizedEditor, contains('HugePdfPolicy.androidCacheExtent'));
    expect(
      normalizedEditor,
      contains('enableLowResolutionPagePreview: !_windows && !_android'),
    );
  });

  test('secondary PDF work waits until the first viewer frame can settle', () {
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(editor, contains('HugePdfPolicy.androidSecondaryWorkDelay'));
    expect(editor, contains('Future<void>.delayed(secondaryDelay'));
    expect(editor, contains('await _loadOutline(document)'));
    expect(editor, contains('await _loadInkWindow(document, _page)'));
    expect(editor, contains('await _selectionMenu.load(document)'));
  });
}

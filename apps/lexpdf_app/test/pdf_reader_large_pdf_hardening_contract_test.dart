import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader keeps bounded progressive rendering for very large PDFs', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart')
        .readAsStringSync();
    final policy = File('lib/src/core/pdf/huge_pdf_policy.dart')
        .readAsStringSync();

    expect(reader, contains('PdfViewer.file('));
    expect(reader, contains('useProgressiveLoading: true'));
    expect(reader, contains('limitRenderingCache: true'));
    expect(
      reader,
      contains('maxImageBytesCachedOnMemory: _renderCacheBudget(context)'),
    );
    expect(reader, contains('HugePdfPolicy.viewerImageCacheBytesFor('));
    expect(reader, contains('pageCount: _activeDocument?.pages.length ?? 0'));
    expect(reader, contains('loadPageDimensionsOnDemand: !_windows'));
    expect(reader, contains('enableLowResolutionPagePreview: false'));
    expect(reader, contains('HugePdfPolicy.androidOnePassRenderingSizeThreshold'));
    expect(reader, contains('HugePdfPolicy.androidCacheExtent'));
    expect(reader, contains('HugePdfPolicy.androidCacheExtent'));
    expect(policy, contains('viewerImageCacheBytes = 64 * 1024 * 1024'));
    expect(policy, contains('_mobileViewerCacheLargeMaxBytes = 24 * 1024 * 1024'));
    expect(policy, contains('_mobileViewerCacheHugeMaxBytes = 16 * 1024 * 1024'));
    expect(policy, contains('_windowsViewerCacheMaxBytes = 100 * 1024 * 1024'));
    expect(policy, contains('androidMaxRenderLongEdge = 2200'));
    expect(policy, contains('androidCacheExtent = 0.12'));
    expect(policy, contains('viewerImageCacheBytesFor'));
  });

  test('reader exposes render failures instead of masking a gray screen', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart')
        .readAsStringSync();

    expect(reader, contains('errorBannerBuilder:'));
    expect(reader, contains('Não foi possível renderizar este PDF.'));
    expect(reader, contains('SelectableText('));
    expect(reader, contains("'\$error'"));
  });

  test('reader hydrates overlays in a bounded page window', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart')
        .readAsStringSync();
    final policy = File('lib/src/core/pdf/huge_pdf_policy.dart')
        .readAsStringSync();

    expect(reader, contains('HugePdfPolicy.overlayWindow('));
    expect(reader, contains('listForPageRange('));
    expect(reader, contains('_overlayLoadGeneration'));
    expect(policy, contains('overlayPagesBefore = 2'));
    expect(policy, contains('overlayPagesAfter = 3'));
  });
}

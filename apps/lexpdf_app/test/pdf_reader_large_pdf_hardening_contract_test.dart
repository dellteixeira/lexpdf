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
      contains('maxImageBytesCachedOnMemory: HugePdfPolicy.viewerImageCacheBytes'),
    );
    expect(reader, contains('loadPageDimensionsOnDemand: true'));
    expect(reader, contains('enableLowResolutionPagePreview: true'));
    expect(reader, contains('onePassRenderingSizeThreshold: 1400'));
    expect(reader, contains('horizontalCacheExtent: 0.30'));
    expect(reader, contains('verticalCacheExtent: 0.30'));
    expect(policy, contains('viewerImageCacheBytes = 64 * 1024 * 1024'));
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

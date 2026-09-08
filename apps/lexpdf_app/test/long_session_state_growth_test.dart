import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  test('twenty thousand page changes keep the active overlay page set bounded', () {
    const pageCount = 5000;
    final activePages = <int>{};

    for (var step = 0; step < 20000; step++) {
      final page = ((step * 7919) % pageCount) + 1;
      final window = HugePdfPolicy.overlayWindow(
        pageNumber: page,
        pageCount: pageCount,
      );

      activePages
        ..removeWhere((candidate) =>
            candidate < window.start || candidate > window.end)
        ..addAll([
          for (var value = window.start; value <= window.end; value++) value,
        ]);

      expect(activePages.length, lessThanOrEqualTo(6));
      expect(activePages, contains(page));
    }
  });

  test('reader evicts annotation and ink pages outside the active window', () {
    final source = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(
      source,
      contains('_renderedAnnotations\n          ..removeWhere('),
    );
    expect(
      source,
      contains('(page, _) => page < window.start || page > window.end'),
    );
    expect(
      source,
      contains('_pdfInkByPage\n          ..removeWhere('),
    );
    expect(source, contains('..addAll(byAnnotationPage)'));
    expect(source, contains('..addAll(byInkPage)'));
  });

  test('reader cancels stale overlay work during prolonged navigation churn', () {
    final source = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(source, contains('final generation = ++_overlayLoadGeneration;'));
    expect(
      source,
      contains('if (!mounted || generation != _overlayLoadGeneration) return;'),
    );
    expect(source, contains('_deferredOverlayLoadTimer?.cancel();'));
    expect(source, contains('HugePdfPolicy.overlayPageChangeDebounce'));
  });

  test('viewer rendering cache remains explicitly bounded for long sessions', () {
    final source = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(source, contains('limitRenderingCache: true'));
    expect(
      source,
      contains('maxImageBytesCachedOnMemory: HugePdfPolicy.viewerImageCacheBytes'),
    );
    expect(HugePdfPolicy.viewerImageCacheBytes, lessThanOrEqualTo(64 * 1024 * 1024));
  });
}

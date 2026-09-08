import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  const pageCount = 5000;

  test('5000-page rapid navigation keeps overlay work bounded', () {
    const jumps = <int>[
      1,
      2500,
      5000,
      2,
      4999,
      800,
      4200,
      1600,
      3200,
      42,
      4958,
    ];

    for (var iteration = 0; iteration < 1000; iteration++) {
      for (final page in jumps) {
        final window = HugePdfPolicy.overlayWindow(
          pageNumber: page,
          pageCount: pageCount,
        );

        expect(window.start, greaterThanOrEqualTo(1));
        expect(window.end, lessThanOrEqualTo(pageCount));
        expect(window.start, lessThanOrEqualTo(page));
        expect(window.end, greaterThanOrEqualTo(page));
        expect(window.end - window.start + 1, lessThanOrEqualTo(6));
      }
    }
  });

  test('5000-page boundary jumps never materialize a document-sized window', () {
    final first = HugePdfPolicy.overlayWindow(
      pageNumber: -1000,
      pageCount: pageCount,
    );
    final last = HugePdfPolicy.overlayWindow(
      pageNumber: 9000,
      pageCount: pageCount,
    );

    expect(first, (start: 1, end: 4));
    expect(last, (start: 4998, end: 5000));
  });

  test('reader restores pages against the loaded document page count', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart')
        .readAsStringSync();

    expect(reader, contains('final count = _viewerController.document.pages.length;'));
    expect(reader, contains('final target = _restoredPage.clamp(1, count);'));
    expect(reader, contains('pageNumber: target'));
  });

  test('rapid page changes are coalesced before overlay hydration', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart')
        .readAsStringSync();

    expect(reader, contains('_deferredOverlayLoadTimer?.cancel();'));
    expect(reader, contains('HugePdfPolicy.overlayPageChangeDebounce'));
    expect(
      HugePdfPolicy.overlayPageChangeDebounce,
      greaterThan(Duration.zero),
    );
    expect(
      HugePdfPolicy.overlayPageChangeDebounce,
      lessThan(const Duration(milliseconds: 250)),
    );
  });
}

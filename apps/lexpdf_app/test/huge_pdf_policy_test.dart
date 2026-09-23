import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  test('OCR render budget never exceeds configured pixel/dimension limits', () {
    final size = HugePdfPolicy.boundedRenderSize(
      pageWidth: 4000,
      pageHeight: 6000,
    );

    expect(size.width, lessThanOrEqualTo(HugePdfPolicy.ocrMaxDimension));
    expect(size.height, lessThanOrEqualTo(HugePdfPolicy.ocrMaxDimension));
    expect(
      size.width * size.height,
      lessThanOrEqualTo(HugePdfPolicy.ocrMaxPixels + 8192),
    );
  });


  test('render cache budget shrinks safely as PDFs become very large', () {
    final normalMobile = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: false,
      pageCount: 200,
      viewportWidth: 900,
      viewportHeight: 1400,
      devicePixelRatio: 2,
    );
    final largeMobile = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: false,
      pageCount: 1267,
      viewportWidth: 900,
      viewportHeight: 1400,
      devicePixelRatio: 2,
    );
    final hugeMobile = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: false,
      pageCount: 5000,
      viewportWidth: 900,
      viewportHeight: 1400,
      devicePixelRatio: 2,
    );

    expect(normalMobile, lessThanOrEqualTo(64 * 1024 * 1024));
    expect(largeMobile, lessThanOrEqualTo(48 * 1024 * 1024));
    expect(hugeMobile, lessThanOrEqualTo(40 * 1024 * 1024));
    expect(normalMobile, greaterThan(largeMobile));
    expect(largeMobile, greaterThan(hugeMobile));

    final normalWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 200,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );
    final largeWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 1267,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );
    final hugeWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 5000,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );

    expect(normalWindows, lessThanOrEqualTo(100 * 1024 * 1024));
    expect(largeWindows, lessThanOrEqualTo(84 * 1024 * 1024));
    expect(hugeWindows, lessThanOrEqualTo(72 * 1024 * 1024));
    expect(normalWindows, greaterThan(largeWindows));
    expect(largeWindows, greaterThan(hugeWindows));
  });

  test('localized index window stays small around the reading page', () {
    final middle = HugePdfPolicy.localizedIndexWindow(
      pageNumber: 2500,
      pageCount: 5000,
    );
    final first = HugePdfPolicy.localizedIndexWindow(
      pageNumber: 1,
      pageCount: 5000,
    );
    final last = HugePdfPolicy.localizedIndexWindow(
      pageNumber: 5000,
      pageCount: 5000,
    );

    expect(middle.start, 2497);
    expect(middle.end, 2506);
    expect(middle.end - middle.start + 1, 10);
    expect(first.start, 1);
    expect(first.end, 7);
    expect(last.start, 4997);
    expect(last.end, 5000);
  });


  test('idle indexing expands outward in bounded chunks', () {
    final localProcessed = <int>{
      for (var page = 497; page <= 506; page++) page,
    };
    final lower = HugePdfPolicy.nextIdleIndexWindow(
      pageNumber: 500,
      pageCount: 5000,
      processedPages: localProcessed,
    );

    expect(lower, isNotNull);
    expect(lower!.start, 485);
    expect(lower.end, 496);
    expect(lower.end - lower.start + 1, HugePdfPolicy.idleIndexChunkPages);

    final lowerAlsoProcessed = <int>{
      for (var page = 485; page <= 506; page++) page,
    };
    final upper = HugePdfPolicy.nextIdleIndexWindow(
      pageNumber: 500,
      pageCount: 5000,
      processedPages: lowerAlsoProcessed,
    );

    expect(upper, isNotNull);
    expect(upper!.start, 507);
    expect(upper.end, 518);
    expect(
      HugePdfPolicy.nextIdleIndexWindow(
        pageNumber: 2,
        pageCount: 3,
        processedPages: {1, 2, 3},
      ),
      isNull,
    );
  });

  test('overlay window stays bounded in a 5000-page PDF', () {
    final middle = HugePdfPolicy.overlayWindow(
      pageNumber: 2500,
      pageCount: 5000,
    );
    final first = HugePdfPolicy.overlayWindow(
      pageNumber: 1,
      pageCount: 5000,
    );
    final last = HugePdfPolicy.overlayWindow(
      pageNumber: 5000,
      pageCount: 5000,
    );

    expect(middle.start, 2498);
    expect(middle.end, 2503);
    expect(middle.end - middle.start + 1, 6);
    expect(first.start, 1);
    expect(first.end, 4);
    expect(last.start, 4998);
    expect(last.end, 5000);
  });
}

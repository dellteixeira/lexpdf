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

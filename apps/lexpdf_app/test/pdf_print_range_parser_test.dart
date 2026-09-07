import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/pdf_print_range_parser.dart';

void main() {
  const parser = PdfPrintRangeParser();

  test('parses ranges, removes duplicates and sorts pages', () {
    expect(
      parser.parse('1-3, 7, 10-12, 3', 20),
      [1, 2, 3, 7, 10, 11, 12],
    );
  });

  test('empty range means all pages', () {
    expect(parser.parse('', 3), [1, 2, 3]);
  });

  test('rejects invalid and out-of-bounds ranges', () {
    expect(() => parser.parse('0', 10), throwsFormatException);
    expect(() => parser.parse('4-2', 10), throwsFormatException);
    expect(() => parser.parse('1-11', 10), throwsFormatException);
    expect(() => parser.parse('abc', 10), throwsFormatException);
  });

  test('rejects invalid document page count', () {
    expect(() => parser.parse('', 0), throwsArgumentError);
  });
}

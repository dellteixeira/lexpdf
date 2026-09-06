import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page range semantics used by print UI', () {
    List<int> parse(String value, int maxPage) {
      final text = value.trim();
      if (text.isEmpty) return List<int>.generate(maxPage, (index) => index + 1);
      final pages = <int>{};
      for (final part in text.split(',')) {
        final token = part.trim();
        if (token.contains('-')) {
          final bits = token.split('-');
          final start = int.parse(bits[0]);
          final end = int.parse(bits[1]);
          for (var page = start; page <= end; page++) pages.add(page);
        } else {
          pages.add(int.parse(token));
        }
      }
      return pages.toList()..sort();
    }

    expect(parse('1-3, 7, 10-12', 20), [1, 2, 3, 7, 10, 11, 12]);
    expect(parse('', 3), [1, 2, 3]);
  });
}

class PdfPrintRangeParser {
  const PdfPrintRangeParser();

  List<int> parse(String value, int maxPage) {
    if (maxPage < 1) {
      throw ArgumentError.value(maxPage, 'maxPage', 'Must be >= 1');
    }
    final text = value.trim();
    if (text.isEmpty) {
      return List<int>.generate(maxPage, (index) => index + 1);
    }

    final pages = <int>{};
    for (final part in text.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token.contains('-')) {
        final bits = token.split('-');
        if (bits.length != 2) throw const FormatException('Faixa inválida.');
        final start = int.tryParse(bits[0].trim());
        final end = int.tryParse(bits[1].trim());
        if (start == null ||
            end == null ||
            start < 1 ||
            end < start ||
            end > maxPage) {
          throw const FormatException('Faixa de páginas inválida.');
        }
        for (var page = start; page <= end; page++) {
          pages.add(page);
        }
      } else {
        final page = int.tryParse(token);
        if (page == null || page < 1 || page > maxPage) {
          throw const FormatException('Número de página inválido.');
        }
        pages.add(page);
      }
    }
    if (pages.isEmpty) {
      throw const FormatException('Nenhuma página selecionada.');
    }
    return pages.toList()..sort();
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Android reader keeps Acrobat-style search inside the PDF', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('button("Buscar") { showSearchBar() }'));
    expect(source, contains('hint = "Localizar palavra ou frase"'));
    expect(source, contains('LexPDF.startSearch('));
    expect(source, contains('LexPDF.previousSearchMatch()'));
    expect(source, contains('LexPDF.nextSearchMatch()'));
    expect(source, contains('fun searchState(payload: String)'));
    expect(source, contains('async function startDocumentSearch('));
    expect(source, contains('async function paintSearchHighlights('));
    expect(source, contains("rgba(255, 152, 0, 0.58)"));
    expect(source, contains("rgba(255, 235, 59, 0.38)"));
    expect(source, contains('Palavra inteira'));
    expect(source, contains('Diferenciar maiúsculas/minúsculas'));
    expect(source, contains('RANGE_CHUNK_SIZE = 512 * 1024'));
  });
}

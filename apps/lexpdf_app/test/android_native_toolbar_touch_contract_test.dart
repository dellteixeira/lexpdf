import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Android PDF toolbar keeps every critical action clickable', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('requestDisallowInterceptTouchEvent(true)'));
    expect(source, contains('requestDisallowInterceptTouchEvent(false)'));
    expect(source, contains('setOnClickListener { onClick() }'));

    expect(source, contains('button("‹") { js("LexPDF.previousPage()") }'));
    expect(source, contains('button("Ir") { showPageJumpDialog() }'));
    expect(source, contains('button("›") { js("LexPDF.nextPage()") }'));
    expect(source, contains('button("−") { js("LexPDF.zoomOut()") }'));
    expect(source, contains('button("+") { js("LexPDF.zoomIn()") }'));
    expect(source, contains('button("⛶ Página") { js("LexPDF.fitPage()") }'));
    expect(source, contains('button("Índice") { showOutlineDialog() }'));
    expect(source, contains('button("Fechar") { finish() }'));
    expect(source, contains('button("Desfazer") { undoInk() }'));
    expect(source, contains('button("Refazer") { redoInk() }'));
  });
}

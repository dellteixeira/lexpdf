import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native reader keeps system bars outside Android toolbar and PDF', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('WindowCompat.setDecorFitsSystemWindows(window, false)'));
    expect(source, contains('ViewCompat.setOnApplyWindowInsetsListener(root)'));
    expect(source, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(source, contains('WindowInsetsCompat.Type.displayCutout()'));
    expect(source, contains('view.setPadding(safe.left, safe.top, safe.right, safe.bottom)'));
    expect(source, contains('ViewCompat.requestApplyInsets(root)'));
    expect(source, contains('setOnClickListener { onClick() }'));
    expect(source, contains('button("Índice") { showOutlineDialog() }'));
    expect(source, contains('button("Fechar") { finish() }'));
    expect(source, contains('HorizontalScrollView(this).apply'));
    expect(source, contains('48.dp'));
  });
}

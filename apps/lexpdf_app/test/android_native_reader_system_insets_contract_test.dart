import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native reader keeps Xiaomi/Android 15 system bars off its toolbar', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('ViewCompat.setOnApplyWindowInsetsListener(root)'));
    expect(source, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(source, contains('WindowInsetsCompat.Type.displayCutout()'));
    expect(
      source,
      contains('view.setPadding(safe.left, safe.top, safe.right, safe.bottom)'),
    );
    expect(source, contains('ViewCompat.requestApplyInsets(root)'));
    expect(source, contains('LinearLayout.LayoutParams.MATCH_PARENT,\n                    48.dp,'));
    expect(source, contains('button("Índice") { showOutlineDialog() }'));
    expect(source, contains('button("Fechar") { finish() }'));
    expect(source, contains('requestDisallowInterceptTouchEvent(true)'));
    expect(source, contains('requestDisallowInterceptTouchEvent(false)'));
  });
}

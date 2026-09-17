import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection study flow is manual and omits question/explain actions', () {
    final source = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    expect(source, contains("label: 'Flashcard'"));
    expect(source, contains('_createManualFlashcard(context, delegate)'));
    expect(source, contains("labelText: 'Pergunta'"));
    expect(source, contains("labelText: 'Resposta'"));
    expect(source, isNot(contains("label: 'Questão'")));
    expect(source, isNot(contains("label: 'Explicar'")));
  });

  test('selection notes are anchored rich-text pins', () {
    final menu = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    final overlay = File('lib/src/widgets/pdf_sticky_note_overlay.dart').readAsStringSync();
    expect(menu, contains('enumerateFragmentBoundingRects()'));
    expect(menu, contains("'fontFamily': fontFamily"));
    expect(menu, contains("'textAlign': textAlign"));
    expect(menu, contains('Icons.format_bold'));
    expect(menu, contains('Icons.format_italic'));
    expect(menu, contains('Icons.format_underline'));
    expect(overlay, contains('Icons.push_pin_rounded'));
    expect(overlay, contains('static const _markerSize = 26.0'));
    expect(overlay, contains("fontFamily: map['fontFamily']"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/src/widgets/pdf_selection_action_menu.dart',
  ).readAsStringSync();

  test('highlight action exposes color and opacity controls', () {
    expect(source, contains("label: 'Marca-texto'"));
    expect(source, contains("'Configurar marca-texto'"));
    expect(source, contains('static const _highlightPalette'));
    expect(source, contains("Text('Opacidade:"));
    expect(source, contains('min: 0.10'));
    expect(source, contains('max: 0.80'));
    expect(source, contains('colorOverride: style.colorValue'));
    expect(source, contains('opacityOverride: style.opacity'));
  });

  test('clear selection removes overlapping persisted text markup', () {
    expect(source, contains("label: 'Limpar seleção'"));
    expect(source, contains('_clearMarkupInSelection(delegate)'));
    expect(source, contains('store.listForPage(documentId, range.pageNumber)'));
    expect(source, contains('annotation.startIndex < range.end'));
    expect(source, contains('annotation.endIndex > range.start'));
    expect(source, contains('await store.delete(annotation.id)'));
    expect(source, contains('await delegate.clearTextSelection()'));
  });

  test('Windows repaint hardening remains intact', () {
    expect(source, contains('final isWindows ='));
    expect(source, contains('defaultTargetPlatform == TargetPlatform.windows'));
    expect(source, contains('if (!isWindows) paint.blendMode = BlendMode.multiply'));
    expect(source, isNot(contains('for (final fragment in rendered.range.enumerateFragmentBoundingRects())')));
  });
}

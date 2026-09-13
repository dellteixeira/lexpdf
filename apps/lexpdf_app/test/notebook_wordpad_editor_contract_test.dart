import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook exposes WordPad-like always-visible text ribbon', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();

    expect(screen, contains("_defaultNotebookFontFamily = 'Arial'"));
    expect(screen, contains('_defaultNotebookFontSize = 12'));
    expect(screen, contains('_buildTextFormattingToolbar(),'));
    expect(screen, isNot(contains("if (_editingTextObjectId != null ||")));
    expect(screen, contains("labelText: 'Fonte'"));
    expect(screen, contains("labelText: 'Tamanho'"));
    expect(screen, contains("tooltip: 'Negrito'"));
    expect(screen, contains("tooltip: 'Itálico'"));
    expect(screen, contains("tooltip: 'Sublinhado'"));
    expect(screen, contains("tooltip: 'Cor da fonte'"));
  });

  test('notebook text starts as Arial 12 and edits directly on page', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final layer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();

    expect(screen, contains('fontSize: _defaultTextFontSize'));
    expect(screen, contains('fontFamily: _defaultTextFontFamily'));
    expect(screen, contains('fontBold: _defaultTextBold'));
    expect(screen, contains('fontItalic: _defaultTextItalic'));
    expect(screen, contains('fontUnderline: _defaultTextUnderline'));
    expect(screen, contains('page.height - (marginY * 2)'));
    expect(screen, contains('onEmptyTap: () {'));
    expect(layer, contains('widget.onEmptyTap?.call()'));
    expect(layer, contains('cursor: editingText'));
    expect(layer, contains('SystemMouseCursors.text'));
    expect(layer, contains("fontFamily: widget.object.fontFamily ?? 'Arial'"));
    expect(layer, contains('fontSize: widget.object.fontSize ?? 12'));
    expect(
      layer,
      isNot(
        contains(
          'border: Border.all(\n          color: Theme.of(context).colorScheme.primary,\n          width: 1.4',
        ),
      ),
    );
  });
}

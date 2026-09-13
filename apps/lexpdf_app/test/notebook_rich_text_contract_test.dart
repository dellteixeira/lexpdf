import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notebook text keeps inline editing and WordPad formatting commands',
    () {
      final screen = File('lib/src/screens/layered_notebook_screen.dart')
          .readAsStringSync();
      final layer = File('lib/src/widgets/notebook_object_layer.dart')
          .readAsStringSync();
      expect(screen, isNot(contains("title: const Text('Inserir texto')")));
      expect(screen, contains('_editingTextObjectId'));
      expect(screen, contains('_buildTextFormattingToolbar'));
      expect(screen, contains('WordPadRibbonGroup'));
      expect(screen, contains('Icons.format_bold'));
      expect(screen, contains('Icons.format_italic'));
      expect(screen, contains('Icons.format_underline'));
      expect(screen, contains('Icons.format_align_left'));
      expect(screen, contains('Icons.format_align_center'));
      expect(screen, contains('Icons.format_align_right'));
      expect(screen, contains('Icons.format_align_justify'));
      expect(screen, contains("tooltip: 'Cor da fonte'"));
      expect(layer, contains('_InlineNotebookTextEditor'));
      expect(layer, contains('TextField('));
      expect(layer, contains('cursorColor:'));
      expect(layer, contains('autofocus: true'));
      expect(layer, contains('_notebookFlutterTextAlign'));
    },
  );

  test('notebook rich text formatting persists in schema v10', () {
    final db = File('lib/src/core/storage/local_database.dart')
        .readAsStringSync();
    final model = File('lib/src/core/notebook/notebook_object_models.dart')
        .readAsStringSync();
    final store = File('lib/src/core/storage/local_notebook_object_store.dart')
        .readAsStringSync();
    expect(db, contains('schemaVersion = 10'));
    expect(db, contains('font_family TEXT'));
    expect(db, contains('font_bold INTEGER'));
    expect(db, contains('font_italic INTEGER'));
    expect(db, contains('font_underline INTEGER'));
    expect(db, contains('text_align TEXT'));
    expect(model, contains('enum NotebookTextAlign'));
    expect(model, contains('final String? fontFamily'));
    expect(model, contains('final bool fontBold'));
    expect(model, contains('final bool fontItalic'));
    expect(model, contains('final bool fontUnderline'));
    expect(model, contains('final NotebookTextAlign textAlign'));
    expect(store, contains("row['font_family']"));
    expect(store, contains("row['font_bold']"));
    expect(store, contains("row['text_align']"));
  });
}

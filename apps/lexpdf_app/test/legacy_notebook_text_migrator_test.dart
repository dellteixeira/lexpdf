import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/notebook/legacy_notebook_text_migrator.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_object_models.dart';

void main() {
  test('legacy text boxes become ordered rich-flow paragraphs', () {
    final now = DateTime.utc(2026, 9, 13);
    NotebookObject text({
      required String id,
      required double x,
      required double y,
      required String value,
      bool bold = false,
      NotebookTextAlign align = NotebookTextAlign.left,
    }) => NotebookObject(
      id: id,
      pageId: 'page-1',
      type: NotebookObjectType.text,
      x: x,
      y: y,
      width: 300,
      height: 80,
      rotation: 0,
      colorValue: 0xFF112233,
      strokeWidth: 1,
      textValue: value,
      fontSize: 14,
      fontFamily: 'Arial',
      fontBold: bold,
      textAlign: align,
      createdAt: now,
      updatedAt: now,
    );

    final root = const LegacyNotebookTextMigrator().migrate([
      text(id: 'b', x: 20, y: 200, value: 'Segundo'),
      text(
        id: 'a',
        x: 10,
        y: 100,
        value: 'Primeiro',
        bold: true,
        align: NotebookTextAlign.center,
      ),
    ]);

    expect(root.text, contains('Primeiro'));
    expect(root.text, contains('Segundo'));
    expect(
      root.text.indexOf('Primeiro'),
      lessThan(root.text.indexOf('Segundo')),
    );
  });
}

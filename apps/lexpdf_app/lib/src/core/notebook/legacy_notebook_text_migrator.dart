import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/services/import_service.dart';

import 'notebook_object_models.dart';

class LegacyNotebookTextMigrator {
  const LegacyNotebookTextMigrator();

  Root migrate(List<NotebookObject> objects) {
    final legacy = objects
        .where((object) => object.type == NotebookObjectType.text)
        .toList(growable: false)
      ..sort((a, b) {
        final y = a.y.compareTo(b.y);
        return y != 0 ? y : a.x.compareTo(b.x);
      });

    if (legacy.isEmpty) {
      return ImportService().importFromHtml('<p></p>');
    }

    final html = StringBuffer();
    for (final object in legacy) {
      final paragraphAlign = switch (object.textAlign) {
        NotebookTextAlign.left => 'left',
        NotebookTextAlign.center => 'center',
        NotebookTextAlign.right => 'right',
        NotebookTextAlign.justify => 'justify',
      };
      final family = _escapeAttribute(object.fontFamily ?? 'Arial');
      final size = object.fontSize ?? 12;
      final weight = object.fontBold ? 'font-weight:700;' : '';
      final italic = object.fontItalic ? 'font-style:italic;' : '';
      final underline = object.fontUnderline
          ? 'text-decoration:underline;'
          : '';
      final color = _cssColor(object.colorValue);
      final text = _escapeText(object.textValue ?? '').replaceAll('\n', '<br/>');
      html
        ..write('<p style="text-align:$paragraphAlign;">')
        ..write(
          '<span style="font-family:$family;font-size:${size}px;color:$color;$weight$italic$underline">',
        )
        ..write(text)
        ..write('</span></p>');
    }
    return ImportService().importFromHtml(html.toString());
  }

  String _cssColor(int value) =>
      '#${(value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  String _escapeText(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _escapeAttribute(String value) => _escapeText(value)
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

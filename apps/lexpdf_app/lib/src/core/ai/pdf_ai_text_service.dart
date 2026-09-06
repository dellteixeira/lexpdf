import 'package:pdfrx/pdfrx.dart';

class PdfAiTextService {
  const PdfAiTextService();

  Future<String> extractDocumentText(
    String path, {
    int maxCharacters = 40000,
  }) async {
    final document = await PdfDocument.openFile(path);
    try {
      final buffer = StringBuffer();
      for (final page in document.pages) {
        final text = await page.loadStructuredText();
        if (text.fullText.trim().isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln('\n--- Página ${page.pageNumber} ---');
        final remaining = maxCharacters - buffer.length;
        if (remaining <= 0) break;
        final value = text.fullText;
        buffer.write(value.length <= remaining ? value : value.substring(0, remaining));
        if (buffer.length >= maxCharacters) break;
      }
      return buffer.toString().trim();
    } finally {
      await document.dispose();
    }
  }
}

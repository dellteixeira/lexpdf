import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/notebook/rtf_document_codec.dart';

void main() {
  const codec = RtfDocumentCodec();

  test('RTF import preserves Unicode paragraphs and common inline styles', () {
    final rtf =
        r'{\rtf1\ansi\uc1\fs24 Texto \b negrito\b0\par A\u231?\u227?o e defesa.}';
    final html = codec.decodeToHtml(
      Uint8List.fromList(rtf.codeUnits),
    );
    expect(html, contains('<strong>negrito</strong>'));
    expect(html, contains('</p><p>'));
    expect(html, contains('Ação e defesa.'));
  });

  test('RTF export emits valid header Unicode and formatting controls', () {
    final bytes = codec.encodeHtml(
      '<p>Texto <strong>forte</strong> e <em>itálico</em>.</p>'
      '<p><u>Constituição</u></p>',
    );
    final rtf = String.fromCharCodes(bytes);
    expect(rtf, startsWith(r'{\rtf1'));
    expect(rtf, contains(r'\b '));
    expect(rtf, contains(r'\i '));
    expect(rtf, contains(r'\ul '));
    expect(rtf, contains(r'\u'));
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/export_service.dart';
import 'package:fluent_editor/services/import_service.dart';

import '../platform/legacy_word_converter.dart';
import 'rtf_document_codec.dart';

class LegacyWordBridgeUnavailable implements Exception {
  const LegacyWordBridgeUnavailable(this.extension);

  final String extension;

  @override
  String toString() =>
      'Conversão ${extension.toUpperCase()} indisponível. No Windows, instale '
      'Microsoft Word ou LibreOffice para habilitar o formato DOC legado.';
}

class NotebookDocumentFileService {
  const NotebookDocumentFileService({
    this.legacyConverter = const LegacyWordConverter(),
    this.rtfCodec = const RtfDocumentCodec(),
  });

  final LegacyWordConverter legacyConverter;
  final RtfDocumentCodec rtfCodec;

  Future<bool> supportsLegacyDoc() => legacyConverter.isAvailable();

  Future<Root> importBytes(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase();
    final importer = ImportService();
    switch (ext) {
      case 'docx':
        return importer.importFromDocx(bytes);
      case 'txt':
        final text = _decodePlainText(bytes);
        return importer.importFromHtml(_plainTextToHtml(text));
      case 'rtf':
        return importer.importFromHtml(rtfCodec.decodeToHtml(bytes));
      case 'doc':
        final docx = await legacyConverter.toDocx(bytes, sourceExtension: ext);
        if (docx == null) throw LegacyWordBridgeUnavailable(ext);
        return importer.importFromDocx(docx);
      default:
        throw UnsupportedError('Formato não suportado: .$ext');
    }
  }

  Future<List<int>> exportBytes(
    FluentDocument document,
    String extension,
  ) async {
    final ext = extension.toLowerCase();
    final exporter = ExportService(document);
    switch (ext) {
      case 'docx':
        return exporter.exportToDocx();
      case 'txt':
        return utf8.encode(document.content.text);
      case 'pdf':
        return exporter.exportToPdf();
      case 'rtf':
        return rtfCodec.encodeHtml(await exporter.exportToHtml());
      case 'doc':
        final docx = await exporter.exportToDocx();
        final converted = await legacyConverter.fromDocx(
          docx,
          targetExtension: ext,
        );
        if (converted == null) throw LegacyWordBridgeUnavailable(ext);
        return converted;
      default:
        throw UnsupportedError('Formato não suportado: .$ext');
    }
  }

  String _decodePlainText(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      // Many Windows-era TXT files are CP-1252 rather than UTF-8. Decode the
      // control range explicitly instead of silently inserting U+FFFD.
      const cp1252 = <int, int>{
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
        0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
        0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
        0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
        0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
        0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
      };
      return String.fromCharCodes(
        bytes.map((byte) => cp1252[byte] ?? byte),
      );
    }
  }

  String _plainTextToHtml(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return escaped.split(RegExp(r'\r?\n')).map((line) => '<p>$line</p>').join();
  }
}

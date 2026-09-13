import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/export_service.dart';
import 'package:fluent_editor/services/import_service.dart';

import '../platform/legacy_word_converter.dart';

class LegacyWordBridgeUnavailable implements Exception {
  const LegacyWordBridgeUnavailable(this.extension);

  final String extension;

  @override
  String toString() =>
      'Conversão ${extension.toUpperCase()} indisponível: configure o bridge nativo/licença Aspose.';
}

class NotebookDocumentFileService {
  const NotebookDocumentFileService({
    this.legacyConverter = const LegacyWordConverter(),
  });

  final LegacyWordConverter legacyConverter;

  Future<Root> importBytes(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase();
    final importer = ImportService();
    switch (ext) {
      case 'docx':
        return importer.importFromDocx(bytes);
      case 'txt':
        final text = utf8.decode(bytes, allowMalformed: true);
        return importer.importFromHtml(_plainTextToHtml(text));
      case 'doc':
      case 'rtf':
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
      case 'doc':
      case 'rtf':
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

  String _plainTextToHtml(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return escaped.split(RegExp(r'\r?\n')).map((line) => '<p>$line</p>').join();
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../core/documents/document_provider.dart';
import '../core/pdf/lexpdf_export_service.dart';
import '../core/pdf/pdf_page_manipulation_service.dart';
import '../core/storage/local_pdf_annotation_object_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_text_annotation_store.dart';

class PdfPrintScreen extends StatefulWidget {
  const PdfPrintScreen({
    required this.document,
    required this.navigationStore,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore navigationStore;

  @override
  State<PdfPrintScreen> createState() => _PdfPrintScreenState();
}

class _PdfPrintScreenState extends State<PdfPrintScreen> {
  final TextEditingController _rangeController = TextEditingController();
  bool _includeAnnotations = true;
  bool _busy = false;
  int? _pageCount;

  @override
  void initState() {
    super.initState();
    _loadPageCount();
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  Future<void> _loadPageCount() async {
    final path = widget.document.localPath;
    if (path == null) return;
    final document = await PdfDocument.openFile(path);
    try {
      if (mounted) setState(() => _pageCount = document.pages.length);
    } finally {
      await document.dispose();
    }
  }

  List<int> _parseRange(String value, int maxPage) {
    final text = value.trim();
    if (text.isEmpty) return List<int>.generate(maxPage, (index) => index + 1);
    final pages = <int>{};
    for (final part in text.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token.contains('-')) {
        final bits = token.split('-');
        if (bits.length != 2) throw const FormatException('Faixa inválida.');
        final start = int.tryParse(bits[0].trim());
        final end = int.tryParse(bits[1].trim());
        if (start == null || end == null || start < 1 || end < start || end > maxPage) {
          throw const FormatException('Faixa de páginas inválida.');
        }
        for (var page = start; page <= end; page++) pages.add(page);
      } else {
        final page = int.tryParse(token);
        if (page == null || page < 1 || page > maxPage) {
          throw const FormatException('Número de página inválido.');
        }
        pages.add(page);
      }
    }
    if (pages.isEmpty) throw const FormatException('Nenhuma página selecionada.');
    return pages.toList()..sort();
  }

  Future<Uint8List> _buildPrintableBytes() async {
    final sourcePath = widget.document.localPath;
    final pageCount = _pageCount;
    if (sourcePath == null || pageCount == null) {
      throw StateError('PDF indisponível para impressão.');
    }
    final pages = _parseRange(_rangeController.text, pageCount);
    String workingPath = sourcePath;
    File? temp;
    if (_includeAnnotations) {
      final db = widget.navigationStore.db;
      final exporter = LexPdfExportService(
        textStore: LocalTextAnnotationStore(db),
        inkStore: LocalPdfInkStore(db),
        objectStore: LocalPdfAnnotationObjectStore(db),
      );
      final flattened = await exporter.exportFlattenedPdf(
        documentId: widget.document.id,
        sourcePath: sourcePath,
      );
      final directory = await getTemporaryDirectory();
      temp = File('${directory.path}${Platform.pathSeparator}lexpdf-print-${DateTime.now().microsecondsSinceEpoch}.pdf');
      await temp.writeAsBytes(flattened, flush: true);
      workingPath = temp.path;
    }

    try {
      if (pages.length == pageCount && pages.first == 1 && pages.last == pageCount) {
        return File(workingPath).readAsBytes();
      }
      final service = const PdfPageManipulationService();
      return service.compose(
        pages
            .map((page) => PdfPageSpec(sourcePath: workingPath, pageNumber: page))
            .toList(growable: false),
        sourceName: 'lexpdf-print.pdf',
      );
    } finally {
      if (temp != null && await temp.exists()) await temp.delete();
    }
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _buildPrintableBytes();
      await Printing.layoutPdf(
        name: widget.document.name,
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível imprimir: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imprimir PDF')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(widget.document.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_pageCount == null ? 'Lendo páginas…' : '$_pageCount páginas'),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir anotações LexPDF'),
            subtitle: const Text('Imprime uma versão achatada com ink, marcações, objetos e assinaturas.'),
            value: _includeAnnotations,
            onChanged: _busy ? null : (value) => setState(() => _includeAnnotations = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rangeController,
            enabled: !_busy && _pageCount != null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Páginas',
              hintText: 'Ex.: 1-3, 7, 10-12 — vazio imprime todas',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || _pageCount == null ? null : _print,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Abrir impressão do sistema'),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

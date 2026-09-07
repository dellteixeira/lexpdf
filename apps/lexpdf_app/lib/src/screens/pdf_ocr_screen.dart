import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/documents/document_provider.dart';
import '../core/ocr/mobile_pdf_ocr_service.dart';
import '../core/ocr/searchable_pdf_exporter.dart';
import '../core/pdf/safe_pdf_writer.dart';
import '../core/storage/local_ocr_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';

class PdfOcrScreen extends StatefulWidget {
  const PdfOcrScreen({
    required this.document,
    required this.navigationStore,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore navigationStore;

  @override
  State<PdfOcrScreen> createState() => _PdfOcrScreenState();
}

class _PdfOcrScreenState extends State<PdfOcrScreen> {
  late final LocalOcrStore _store;
  late final MobilePdfOcrService _service;
  List<OcrPageResult> _results = const [];
  PdfOcrProgress? _progress;
  PdfOcrSummary? _summary;
  bool _processing = false;
  bool _exporting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _store = LocalOcrStore(widget.navigationStore.db);
    _service = MobilePdfOcrService(
      ocrStore: _store,
      navigationStore: widget.navigationStore,
    );
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final values = await _store.listForDocument(widget.document.id);
    if (!mounted) return;
    setState(() => _results = values);
  }

  Future<void> _run() async {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty || _processing) return;
    setState(() {
      _processing = true;
      _progress = null;
      _summary = null;
      _error = null;
    });
    try {
      final summary = await _service.process(
        documentId: widget.document.id,
        filePath: path,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      await _reload();
      if (mounted) setState(() => _summary = summary);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<String?> _chooseExportPath() async {
    final baseName = widget.document.name.toLowerCase().endsWith('.pdf')
        ? widget.document.name.substring(0, widget.document.name.length - 4)
        : widget.document.name;
    final suggested = '${baseName}_pesquisavel.pdf';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(suggestedName: suggested);
      return location?.path;
    }
    final app = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${app.path}${Platform.pathSeparator}LexPDF${Platform.pathSeparator}exports',
    );
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$suggested';
  }

  Future<void> _exportSearchable() async {
    final sourcePath = widget.document.localPath;
    if (sourcePath == null || sourcePath.isEmpty || _results.isEmpty || _exporting) {
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final destination = await _chooseExportPath();
      if (destination == null) return;
      final bytes = await SearchablePdfExporter(ocrStore: _store).export(
        documentId: widget.document.id,
        sourcePath: sourcePath,
      );
      await const SafePdfWriter().saveAs(
        bytes: bytes,
        destinationPath: destination,
        replaceExisting: Platform.isAndroid || Platform.isIOS,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF pesquisável salvo em: $destination')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR offline')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              _service.nativeOcrSupported
                  ? 'OCR local por ML Kit. O processamento acontece no aparelho, preserva a geometria das linhas e entra na busca FTS5 offline.'
                  : 'Nesta plataforma o LexPDF indexa o texto já incorporado ao PDF. PDFs somente-imagem exigem o engine OCR móvel local; a extração de texto desktop não é apresentada como OCR.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _processing || !widget.document.availableOffline ? null : _run,
                  icon: _processing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined),
                  label: const Text('Processar documento'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting || _processing || _results.isEmpty
                      ? null
                      : _exportSearchable,
                  icon: _exporting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.find_in_page_outlined),
                  label: const Text('Exportar PDF pesquisável'),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.pageCount == 0
                    ? null
                    : progress.pageNumber / progress.pageCount,
              ),
              const SizedBox(height: 4),
              Text('Página ${progress.pageNumber} de ${progress.pageCount}'),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 12),
              Text(
                '${_summary!.recognizedPages}/${_summary!.pageCount} páginas com texto • ${_summary!.engine}',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                'Operação não concluída: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Text('Texto indexado', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Nenhuma página processada ainda.'))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text('${result.pageNumber}')),
                          title: Text(
                            result.text.isEmpty ? 'Nenhum texto reconhecido' : result.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            result.lines.isEmpty
                                ? result.engine
                                : '${result.engine} • ${result.lines.length} linhas posicionadas',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/documents/document_provider.dart';
import '../core/ocr/mobile_pdf_ocr_service.dart';
import '../core/ocr/searchable_pdf_exporter.dart';
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
  final TextEditingController _startPage = TextEditingController(text: '1');
  final TextEditingController _endPage = TextEditingController();
  List<OcrPageResult> _results = const [];
  PdfOcrProgress? _progress;
  PdfOcrSummary? _summary;
  ({int completed, int total})? _exportProgress;
  bool _processing = false;
  bool _exporting = false;
  bool _cancelRequested = false;
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

  @override
  void dispose() {
    _cancelRequested = true;
    _startPage.dispose();
    _endPage.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final values = await _store.listForDocument(widget.document.id);
    if (!mounted) return;
    setState(() => _results = values);
  }

  Future<void> _run() async {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty || _processing) return;
    final start = int.tryParse(_startPage.text.trim()) ?? 1;
    final endText = _endPage.text.trim();
    final end = endText.isEmpty ? null : int.tryParse(endText);
    if (start < 1 || (end != null && end < start)) {
      setState(() => _error = 'Intervalo de páginas inválido.');
      return;
    }
    setState(() {
      _processing = true;
      _cancelRequested = false;
      _progress = null;
      _summary = null;
      _error = null;
    });
    try {
      final summary = await _service.process(
        documentId: widget.document.id,
        filePath: path,
        startPage: start,
        endPage: end,
        isCancelled: () => _cancelRequested,
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
      _exportProgress = null;
      _error = null;
    });
    try {
      final destination = await _chooseExportPath();
      if (destination == null) return;
      final summary = await SearchablePdfExporter(ocrStore: _store).exportToFile(
        documentId: widget.document.id,
        sourcePath: sourcePath,
        outputPath: destination,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() => _exportProgress = (completed: completed, total: total));
          }
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF pesquisável salvo em: ${summary.file.path} • '
            '${summary.injectedPages} página(s) receberam camada OCR; '
            '${summary.alreadySearchablePages} já tinham texto vetorial.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final exportProgress = _exportProgress;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR e indexação offline')),
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
                  ? 'Processamento local e offline. Texto incorporado é indexado sem rasterização; páginas digitalizadas usam OCR nativo página a página, com memória limitada e retomada.'
                  : 'Nesta plataforma o LexPDF indexa o texto já incorporado ao PDF.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startPage,
                    enabled: !_processing,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Página inicial',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _endPage,
                    enabled: !_processing,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Página final',
                      hintText: 'até o fim',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                  label: Text(_processing ? 'Processando…' : 'Processar intervalo'),
                ),
                if (_processing)
                  OutlinedButton.icon(
                    onPressed: _cancelRequested
                        ? null
                        : () => setState(() => _cancelRequested = true),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar'),
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
                value: progress.totalInRange == 0
                    ? null
                    : progress.completedInRange / progress.totalInRange,
              ),
              const SizedBox(height: 4),
              Text(
                'Página ${progress.pageNumber}/${progress.pageCount} • '
                '${progress.completedInRange}/${progress.totalInRange} no intervalo'
                '${progress.skipped ? ' • já processada' : ''}',
              ),
            ],
            if (exportProgress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: exportProgress.total == 0
                    ? null
                    : exportProgress.completed / exportProgress.total,
              ),
              const SizedBox(height: 4),
              Text(
                'Exportação vetorial: página ${exportProgress.completed} de ${exportProgress.total}',
              ),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 12),
              Text(
                '${_summary!.recognizedPages} página(s) com texto neste processamento • '
                '${_summary!.embeddedTextPages} sem rasterização • '
                '${_summary!.rasterizedPages} com OCR raster • '
                '${_summary!.cancelled ? 'interrompido e salvo para retomada' : 'concluído'}',
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

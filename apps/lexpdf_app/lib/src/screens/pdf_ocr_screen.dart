import 'dart:async';

import 'package:flutter/material.dart';

import '../core/documents/document_provider.dart';
import '../core/ocr/mobile_pdf_ocr_service.dart';
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
                  ? 'OCR local por ML Kit. O processamento acontece no aparelho e o texto reconhecido entra na busca offline.'
                  : 'Nesta plataforma o OCR nativo ainda não está disponível. O LexPDF indexará o texto já incorporado ao PDF; PDFs somente-imagem exigem o engine móvel local.',
            ),
            const SizedBox(height: 16),
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
                'Falha no OCR: $_error',
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
                          subtitle: Text(result.engine),
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

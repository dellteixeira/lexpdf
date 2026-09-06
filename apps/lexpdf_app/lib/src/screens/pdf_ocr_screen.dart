import 'dart:io';

import 'package:flutter/material.dart';

import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/ocr/local_pdf_ocr_service.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_pdf_navigation_store.dart';

class PdfOcrScreen extends StatefulWidget {
  const PdfOcrScreen({
    required this.catalog,
    required this.searchStore,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalPdfNavigationStore searchStore;

  @override
  State<PdfOcrScreen> createState() => _PdfOcrScreenState();
}

class _PdfOcrScreenState extends State<PdfOcrScreen> {
  final DocumentPickerService _picker = const DocumentPickerService();
  DocumentRef? _document;
  List<PdfOcrPageResult> _results = const [];
  bool _running = false;
  bool _forceOcr = false;
  int _completed = 0;
  int _total = 0;
  String? _error;

  bool get _nativeOcrSupported =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR offline')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.document_scanner_outlined, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _document?.name ?? 'Nenhum PDF selecionado',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _running ? null : _pickDocument,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Selecionar PDF'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _nativeOcrSupported
                          ? 'OCR executado localmente no dispositivo. Nenhuma página é enviada para a Internet.'
                          : 'Nesta plataforma, o LexPDF indexará apenas o texto já existente no PDF. OCR de imagem está disponível em Android, Windows e macOS.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Forçar OCR em todas as páginas'),
                      subtitle: const Text(
                        'Desativado: páginas que já possuem texto utilizam extração nativa, economizando processamento.',
                      ),
                      value: _forceOcr,
                      onChanged: _running
                          ? null
                          : (value) => setState(() => _forceOcr = value),
                    ),
                    FilledButton.icon(
                      onPressed: _document == null || _running ? null : _runOcr,
                      icon: _running
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(_running ? 'Processando $_completed/$_total' : 'Executar e indexar'),
                    ),
                    if (_running && _total > 0) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _completed / _total),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_results.isNotEmpty)
              Text(
                '${_results.length} página(s) indexadas • ${_results.where((item) => item.usedOcr).length} por OCR',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      child: Text(
                        'O texto reconhecido será salvo no índice local e ficará disponível na busca do LexPDF.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${result.pageNumber}')),
                            title: Text(result.usedOcr ? 'OCR local' : 'Texto nativo do PDF'),
                            subtitle: Text(
                              result.text.isEmpty ? 'Nenhum texto reconhecido.' : result.text,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
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

  Future<void> _pickDocument() async {
    final selected = await _picker.pickPdf();
    if (!mounted || selected == null) return;
    await widget.catalog.upsert(selected);
    final stored = await widget.catalog.getById(selected.id) ?? selected;
    setState(() {
      _document = stored;
      _results = const [];
      _error = null;
    });
  }

  Future<void> _runOcr() async {
    final document = _document;
    final path = document?.localPath;
    if (document == null || path == null || path.isEmpty) return;
    setState(() {
      _running = true;
      _completed = 0;
      _total = 0;
      _error = null;
    });
    try {
      final service = LocalPdfOcrService(searchStore: widget.searchStore);
      final results = await service.recognizeDocument(
        documentId: document.id,
        filePath: path,
        forceOcr: _forceOcr,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = 'Falha no OCR: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}

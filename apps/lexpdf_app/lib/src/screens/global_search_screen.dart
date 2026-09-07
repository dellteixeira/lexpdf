import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_global_search_fts.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import 'pdf_navigation_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({
    required this.catalog,
    required this.store,
    super.key,
  });

  final LocalDocumentCatalog catalog;
  final LocalPdfNavigationStore store;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _query = TextEditingController();
  List<LocalSearchHit> _hits = const [];
  bool _searching = false;
  bool _indexing = false;
  bool _cancelIndexing = false;
  String _indexStatus = '';

  LocalGlobalSearchFts get _fts => LocalGlobalSearchFts(widget.store.db);

  @override
  void dispose() {
    _cancelIndexing = true;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Busca local'),
        actions: [
          if (_indexing)
            IconButton(
              tooltip: 'Cancelar indexação',
              onPressed: () => setState(() => _cancelIndexing = true),
              icon: const Icon(Icons.stop_circle_outlined),
            )
          else
            IconButton(
              tooltip: 'Indexar PDFs locais',
              onPressed: _indexAllLocalPdfs,
              icon: const Icon(Icons.manage_search_outlined),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'Pesquisar PDFs, anotações e cadernos',
                suffixIcon: IconButton(
                  tooltip: 'Pesquisar',
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            if (_indexStatus.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _indexStatus,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _hits.isEmpty
                      ? const Center(
                          child: Text(
                            'Digite um termo. Para pesquisar o conteúdo integral dos PDFs, use “Indexar PDFs locais” uma vez.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _hits.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _hitTile(_hits[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hitTile(LocalSearchHit hit) {
    final icon = switch (hit.kind) {
      'pdf_text' => Icons.text_snippet_outlined,
      'annotation' => Icons.edit_note_outlined,
      'notebook' => Icons.menu_book_outlined,
      _ => Icons.picture_as_pdf_outlined,
    };
    final subtitle = hit.pageNumber == null
        ? hit.snippet
        : 'Página ${hit.pageNumber} • ${hit.snippet}';
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: hit.documentId == null ? null : const Icon(Icons.chevron_right),
        onTap: hit.documentId == null ? null : () => _openHit(hit),
      ),
    );
  }

  Future<void> _search() async {
    final value = _query.text.trim();
    if (value.isEmpty) return;
    setState(() => _searching = true);
    try {
      final hits = await _fts.search(value, limit: 200);
      if (!mounted) return;
      setState(() => _hits = hits);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openHit(LocalSearchHit hit) async {
    final id = hit.documentId;
    if (id == null) return;
    final document = await widget.catalog.getById(id);
    if (!mounted || document == null || !document.availableOffline) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfNavigationScreen(
          document: document,
          store: widget.store,
          initialPage: hit.pageNumber ?? 1,
        ),
      ),
    );
  }

  Future<void> _indexAllLocalPdfs() async {
    if (_indexing) return;
    setState(() {
      _indexing = true;
      _cancelIndexing = false;
      _indexStatus = 'Preparando indexação local…';
    });
    var indexed = 0;
    var failed = 0;
    var cancelled = false;
    try {
      await pdfrxFlutterInitialize();
      final documents = await widget.catalog.list(limit: 1000);
      for (var i = 0; i < documents.length; i++) {
        if (_cancelIndexing) {
          cancelled = true;
          break;
        }
        final item = documents[i];
        final path = item.localPath;
        if (path == null || path.isEmpty || !item.availableOffline) continue;
        if (mounted) {
          setState(() {
            _indexStatus = 'Indexando ${i + 1}/${documents.length}: ${item.name}';
          });
        }
        PdfDocument? pdf;
        try {
          pdf = await PdfDocument.openFile(path);
          widget.store.db.database.execute(
            'DELETE FROM pdf_page_text_index WHERE document_id = ?;',
            [item.id],
          );
          for (var pageNumber = 1; pageNumber <= pdf.pages.length; pageNumber++) {
            if (_cancelIndexing) {
              cancelled = true;
              break;
            }
            final page = pdf.pages[pageNumber - 1];
            final text = await page.loadStructuredText();
            widget.store.db.database.execute('''
              INSERT INTO pdf_page_text_index(
                document_id, page_number, content, indexed_at
              ) VALUES (?, ?, ?, ?)
              ON CONFLICT(document_id, page_number) DO UPDATE SET
                content = excluded.content,
                indexed_at = excluded.indexed_at;
            ''', [
              item.id,
              pageNumber,
              text.fullText,
              DateTime.now().toUtc().toIso8601String(),
            ]);
            if (mounted && (pageNumber == 1 || pageNumber % 25 == 0)) {
              setState(() {
                _indexStatus =
                    'Indexando ${i + 1}/${documents.length}: ${item.name} · página $pageNumber/${pdf!.pages.length}';
              });
            }
            if (pageNumber % 8 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
          }
          if (cancelled) break;
          indexed++;
        } catch (_) {
          failed++;
        } finally {
          await pdf?.dispose();
        }
      }
      await _fts.rebuild();
    } finally {
      if (mounted) {
        setState(() {
          _indexing = false;
          _indexStatus = cancelled
              ? 'Indexação interrompida. O conteúdo já processado foi preservado.'
              : 'Indexação FTS5 concluída: $indexed PDF(s); $failed falha(s).';
        });
      }
    }
    if (!cancelled && _query.text.trim().isNotEmpty) await _search();
  }
}

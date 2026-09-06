import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_reading_progress_store.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    required this.document,
    required this.readingProgress,
    super.key,
  });

  final DocumentRef document;
  final LocalReadingProgressStore readingProgress;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late final Future<ReadingProgressState?> _initialProgress =
      widget.readingProgress.get(widget.document.id);
  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  late final PdfTextSearcher _textSearcher =
      PdfTextSearcher(_viewerController)..addListener(_onSearchChanged);

  int? _currentPage;
  bool _searchMode = false;

  @override
  void dispose() {
    _textSearcher.removeListener(_onSearchChanged);
    _textSearcher.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.document.name)),
        body: const Center(
          child: Text('Este documento ainda não está disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar no documento',
                  border: InputBorder.none,
                ),
                onSubmitted: _startSearch,
              )
            : Text(
                widget.document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        actions: _searchMode ? _buildSearchActions() : _buildReaderActions(),
      ),
      body: FutureBuilder<ReadingProgressState?>(
        future: _initialProgress,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final initialPage = snapshot.data?.pageNumber ?? 1;
          _currentPage ??= initialPage;

          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: PdfViewer.file(
              path,
              controller: _viewerController,
              initialPageNumber: initialPage,
              params: PdfViewerParams(
                textSelectionParams:
                    const PdfTextSelectionParams(enabled: true),
                pagePaintCallbacks: [
                  _textSearcher.pageTextMatchPaintCallback,
                ],
                onPageChanged: (pageNumber) {
                  if (pageNumber == null) return;
                  if (_currentPage != pageNumber && mounted) {
                    setState(() => _currentPage = pageNumber);
                  }
                  unawaited(
                    widget.readingProgress.save(
                      documentId: widget.document.id,
                      pageNumber: pageNumber,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildReaderActions() {
    return [
      if (_currentPage != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(child: Text('Pág. $_currentPage')),
        ),
      IconButton(
        tooltip: 'Pesquisar no PDF',
        onPressed: () => setState(() => _searchMode = true),
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: 'Anotações',
        onPressed: null,
        icon: const Icon(Icons.draw_outlined),
      ),
      IconButton(
        tooltip: 'Imprimir',
        onPressed: null,
        icon: const Icon(Icons.print_outlined),
      ),
    ];
  }

  List<Widget> _buildSearchActions() {
    final currentIndex = _textSearcher.currentIndex;
    final matchCount = _textSearcher.matches.length;

    return [
      if (_textSearcher.isSearching)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              matchCount == 0
                  ? '0 resultados'
                  : '${(currentIndex ?? 0) + 1}/$matchCount',
            ),
          ),
        ),
      IconButton(
        tooltip: 'Resultado anterior',
        onPressed: matchCount == 0
            ? null
            : () => unawaited(_textSearcher.goToPrevMatch()),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: 'Próximo resultado',
        onPressed: matchCount == 0
            ? null
            : () => unawaited(_textSearcher.goToNextMatch()),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      IconButton(
        tooltip: 'Fechar pesquisa',
        onPressed: _closeSearch,
        icon: const Icon(Icons.close),
      ),
    ];
  }

  void _startSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _textSearcher.resetTextSearch();
      return;
    }
    _textSearcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _closeSearch() {
    _textSearcher.resetTextSearch();
    _searchController.clear();
    setState(() => _searchMode = false);
  }
}

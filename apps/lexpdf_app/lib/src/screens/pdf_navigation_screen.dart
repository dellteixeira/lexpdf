import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import 'pdf_page_tools_screen.dart';

class PdfNavigationScreen extends StatefulWidget {
  const PdfNavigationScreen({
    required this.document,
    required this.store,
    this.initialPage = 1,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore store;
  final int initialPage;

  @override
  State<PdfNavigationScreen> createState() => _PdfNavigationScreenState();
}

enum _PdfViewMode { continuous, horizontal, facing }

class _PdfNavigationScreenState extends State<PdfNavigationScreen> {
  final PdfViewerController _controller = PdfViewerController();
  final List<int> _backHistory = [];
  final List<int> _forwardHistory = [];
  List<PdfBookmark> _bookmarks = const [];
  List<PdfOutlineNode> _outline = const [];
  PdfDocument? _document;
  int _page = 1;
  bool _historyNavigation = false;
  _PdfViewMode _viewMode = _PdfViewMode.continuous;

  @override
  void initState() {
    super.initState();
    _page = math.max(1, widget.initialPage);
    unawaited(_reloadBookmarks());
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navegação PDF')),
        body: const Center(child: Text('O PDF precisa estar disponível offline.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Navegação PDF'),
            Text(
              widget.document.name,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voltar na navegação',
            onPressed: _backHistory.isEmpty ? null : _goBack,
            icon: const Icon(Icons.arrow_back_outlined),
          ),
          IconButton(
            tooltip: 'Avançar na navegação',
            onPressed: _forwardHistory.isEmpty ? null : _goForward,
            icon: const Icon(Icons.arrow_forward_outlined),
          ),
          IconButton(
            tooltip: 'Ir para página',
            onPressed: _jumpToPage,
            icon: const Icon(Icons.numbers_outlined),
          ),
          IconButton(
            tooltip: 'Miniaturas',
            onPressed: _document == null ? null : () => _showThumbnails(path),
            icon: const Icon(Icons.grid_view_outlined),
          ),
          IconButton(
            tooltip: 'Sumário / outline',
            onPressed: _outline.isEmpty ? null : _showOutline,
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Marcadores',
            onPressed: _showBookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Marcar página $_page',
            onPressed: _toggleCurrentBookmark,
            icon: Icon(
              _bookmarks.any((item) => item.pageNumber == _page)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
          ),
          IconButton(
            tooltip: 'Gerenciar páginas',
            onPressed: _openPageTools,
            icon: const Icon(Icons.view_week_outlined),
          ),
          PopupMenuButton<_PdfViewMode>(
            tooltip: 'Modo de visualização',
            initialValue: _viewMode,
            onSelected: (value) {
              setState(() => _viewMode = value);
              _controller.invalidate();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PdfViewMode.continuous,
                child: Text('Contínuo vertical'),
              ),
              PopupMenuItem(
                value: _PdfViewMode.horizontal,
                child: Text('Horizontal'),
              ),
              PopupMenuItem(
                value: _PdfViewMode.facing,
                child: Text('Páginas duplas'),
              ),
            ],
            icon: const Icon(Icons.view_carousel_outlined),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: Text('$_page')),
          ),
        ],
      ),
      body: PdfViewer.file(
        path,
        controller: _controller,
        initialPageNumber: _page,
        params: PdfViewerParams(
          layoutPages: switch (_viewMode) {
            _PdfViewMode.continuous => null,
            _PdfViewMode.horizontal => _horizontalLayout,
            _PdfViewMode.facing => _facingLayout,
          },
          linkHandlerParams: PdfLinkHandlerParams(
            onLinkTap: (link) {
              final dest = link.dest;
              if (dest != null) {
                unawaited(_controller.goToDest(dest));
              }
            },
          ),
          onViewerReady: (document, controller) {
            _document = document;
            unawaited(_loadOutline(document));
          },
          onPageChanged: _onPageChanged,
        ),
      ),
    );
  }

  Future<void> _openPageTools() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPageToolsScreen(document: widget.document),
      ),
    );
  }

  Future<void> _reloadBookmarks() async {
    final values = await widget.store.listBookmarks(widget.document.id);
    if (!mounted) return;
    setState(() => _bookmarks = values);
  }

  Future<void> _loadOutline(PdfDocument document) async {
    final values = await document.loadOutline();
    if (!mounted) return;
    setState(() => _outline = values);
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null || pageNumber == _page) return;
    final previous = _page;
    setState(() => _page = pageNumber);
    if (_historyNavigation) {
      _historyNavigation = false;
      return;
    }
    if (_backHistory.isEmpty || _backHistory.last != previous) {
      _backHistory.add(previous);
      if (_backHistory.length > 100) _backHistory.removeAt(0);
    }
    _forwardHistory.clear();
  }

  Future<void> _goBack() async {
    if (_backHistory.isEmpty) return;
    final target = _backHistory.removeLast();
    _forwardHistory.add(_page);
    _historyNavigation = true;
    await _controller.goToPage(pageNumber: target, anchor: PdfPageAnchor.top);
    if (mounted) setState(() {});
  }

  Future<void> _goForward() async {
    if (_forwardHistory.isEmpty) return;
    final target = _forwardHistory.removeLast();
    _backHistory.add(_page);
    _historyNavigation = true;
    await _controller.goToPage(pageNumber: target, anchor: PdfPageAnchor.top);
    if (mounted) setState(() {});
  }

  Future<void> _jumpToPage() async {
    final controller = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir para página'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Número da página'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Ir'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || page < 1) return;
    final maxPage = _document?.pages.length;
    if (maxPage != null && page > maxPage) return;
    await _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.top);
  }

  Future<void> _toggleCurrentBookmark() async {
    await widget.store.toggleBookmark(
      documentId: widget.document.id,
      pageNumber: _page,
    );
    await _reloadBookmarks();
  }

  Future<void> _showBookmarks() async {
    final values = await widget.store.listBookmarks(widget.document.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: values.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('Nenhum marcador criado.')),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final bookmark = values[index];
                  return ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(bookmark.label),
                    subtitle: Text('Página ${bookmark.pageNumber}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_controller.goToPage(
                        pageNumber: bookmark.pageNumber,
                        anchor: PdfPageAnchor.top,
                      ));
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showOutline() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [for (final node in _outline) _outlineTile(node, 0)],
          ),
        ),
      ),
    );
  }

  Widget _outlineTile(PdfOutlineNode node, int depth) {
    final children = node.children;
    if (children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 8),
        title: Text(node.title),
        subtitle: node.dest == null ? null : Text('Página ${node.dest!.pageNumber}'),
        onTap: node.dest == null
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_controller.goToDest(node.dest));
              },
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 8),
      title: Text(node.title),
      subtitle: node.dest == null ? null : Text('Página ${node.dest!.pageNumber}'),
      children: [for (final child in children) _outlineTile(child, depth + 1)],
    );
  }

  Future<void> _showThumbnails(String path) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: PdfDocumentViewBuilder.file(
            path,
            builder: (context, document) {
              final count = document?.pages.length ?? 0;
              if (document == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 230,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: count,
                itemBuilder: (context, index) {
                  final pageNumber = index + 1;
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_controller.goToPage(
                        pageNumber: pageNumber,
                        anchor: PdfPageAnchor.top,
                      ));
                    },
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(
                            child: PdfPageView(
                              document: document,
                              pageNumber: pageNumber,
                              maximumDpi: 110,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text('Página $pageNumber'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height = pages.fold<double>(
          0,
          (previous, page) => math.max(previous, page.height),
        ) +
        params.margin * 2;
    final layouts = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      layouts.add(Rect.fromLTWH(
        x,
        (height - page.height) / 2,
        page.width,
        page.height,
      ));
      x += page.width + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(x, height),
    );
  }

  PdfPageLayout _facingLayout(List<PdfPage> pages, PdfViewerParams params) {
    final maxWidth = pages.fold<double>(
      0,
      (previous, page) => math.max(previous, page.width),
    );
    final layouts = <Rect>[];
    var y = params.margin;
    for (var i = 0; i < pages.length; i += 2) {
      final left = pages[i];
      final right = i + 1 < pages.length ? pages[i + 1] : null;
      final rowHeight = math.max(left.height, right?.height ?? 0);
      layouts.add(Rect.fromLTWH(
        params.margin + maxWidth - left.width,
        y + (rowHeight - left.height) / 2,
        left.width,
        left.height,
      ));
      if (right != null) {
        layouts.add(Rect.fromLTWH(
          params.margin * 2 + maxWidth,
          y + (rowHeight - right.height) / 2,
          right.width,
          right.height,
        ));
      }
      y += rowHeight + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(params.margin * 3 + maxWidth * 2, y),
    );
  }
}

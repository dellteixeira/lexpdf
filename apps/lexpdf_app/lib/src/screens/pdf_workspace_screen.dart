import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/documents/document_provider.dart';
import '../core/pdf/huge_pdf_policy.dart';
import '../core/storage/local_pdf_form_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'pdf_advanced_annotation_screen.dart';
import 'pdf_export_screen.dart';
import 'pdf_forms_screen.dart';
import 'pdf_ocr_screen.dart';
import 'pdf_page_tools_screen.dart';
import 'pdf_print_screen.dart';

enum _PdfViewMode { continuous, horizontal, facing }

enum _WorkspaceMoreAction { forms, export, print }

class PdfWorkspaceScreen extends StatefulWidget {
  const PdfWorkspaceScreen({
    required this.document,
    required this.store,
    required this.annotations,
    this.initialPage = 1,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfNavigationStore store;
  final LocalTextAnnotationStore annotations;
  final int initialPage;

  @override
  State<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen> {
  static const _zoomPresets = <int>[25, 50, 75, 100, 125, 150, 200, 300, 400];

  final PdfViewerController _controller = PdfViewerController();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'pdf-workspace');
  final List<int> _backHistory = <int>[];
  final List<int> _forwardHistory = <int>[];

  List<PdfBookmark> _bookmarks = const <PdfBookmark>[];
  List<PdfOutlineNode> _outline = const <PdfOutlineNode>[];
  PdfDocument? _document;
  int _page = 1;
  int _zoomPercent = 100;
  bool _historyNavigation = false;
  _PdfViewMode _viewMode = _PdfViewMode.continuous;

  @override
  void initState() {
    super.initState();
    _page = math.max(1, widget.initialPage);
    _controller.addListener(_syncZoomFromController);
    unawaited(_reloadBookmarks());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncZoomFromController);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF')),
        body: const Center(
          child: Text('O PDF precisa estar disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PDF'),
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
            tooltip: 'Zoom -',
            onPressed: _zoomOut,
            icon: const Icon(Icons.zoom_out),
          ),
          _buildZoomMenu(compact: true),
          IconButton(
            tooltip: 'Zoom +',
            onPressed: _zoomIn,
            icon: const Icon(Icons.zoom_in),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: Text('Pág. $_page')),
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            unawaited(_previousPage());
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            unawaited(_nextPage());
          },
          const SingleActivator(LogicalKeyboardKey.arrowUp): () {
            unawaited(_scrollBy(110));
          },
          const SingleActivator(LogicalKeyboardKey.arrowDown): () {
            unawaited(_scrollBy(-110));
          },
          const SingleActivator(LogicalKeyboardKey.pageUp): () {
            unawaited(_previousPage());
          },
          const SingleActivator(LogicalKeyboardKey.pageDown): () {
            unawaited(_nextPage());
          },
        },
        child: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          child: Column(
            children: [
              _buildCommandBar(path),
              const Divider(height: 1),
              Expanded(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: PdfViewer.file(
                    path,
                    controller: _controller,
                    initialPageNumber: _page,
                    useProgressiveLoading: true,
                    params: PdfViewerParams(
                      limitRenderingCache: true,
                      maxImageBytesCachedOnMemory:
                          HugePdfPolicy.viewerImageCacheBytes,
                      horizontalCacheExtent: 0.30,
                      verticalCacheExtent: 0.30,
                      onePassRenderingSizeThreshold: 1400,
                      behaviorControlParams:
                          const PdfViewerBehaviorControlParams(
                        loadPageDimensionsOnDemand: true,
                        enableLowResolutionPagePreview: true,
                        trailingPageLoadingDelay: Duration(milliseconds: 250),
                        pageImageCachingDelay: Duration(milliseconds: 40),
                        partialImageLoadingDelay: Duration(milliseconds: 60),
                      ),
                      layoutPages: switch (_viewMode) {
                        _PdfViewMode.continuous => null,
                        _PdfViewMode.horizontal => _horizontalLayout,
                        _PdfViewMode.facing => _facingLayout,
                      },
                      linkHandlerParams: PdfLinkHandlerParams(
                        onLinkTap: (link) {
                          final url = link.url;
                          if (url != null) {
                            unawaited(_openExternalLink(url));
                            return;
                          }
                          final dest = link.dest;
                          if (dest != null) {
                            unawaited(_controller.goToDest(dest));
                          }
                        },
                      ),
                      onViewerReady: (document, controller) {
                        _document = document;
                        _syncZoomFromController();
                        if (mounted) setState(() {});
                        unawaited(_loadOutline(document));
                      },
                      onPageChanged: _onPageChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommandBar(String path) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 56,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
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
                tooltip: 'Página anterior (←)',
                onPressed: _page <= 1 ? null : _previousPage,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Próxima página (→)',
                onPressed: _document != null && _page >= _document!.pages.length
                    ? null
                    : _nextPage,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Ir para página',
                onPressed: _jumpToPage,
                icon: const Icon(Icons.numbers_outlined),
              ),
              const VerticalDivider(width: 20),
              _CommandButton(
                icon: Icons.grid_view_outlined,
                label: 'Miniaturas',
                onPressed:
                    _document == null ? null : () => _showThumbnails(path),
              ),
              _CommandButton(
                icon: Icons.account_tree_outlined,
                label: 'Sumário',
                onPressed: _outline.isEmpty ? null : _showOutline,
              ),
              _CommandButton(
                icon: Icons.bookmarks_outlined,
                label: 'Marcadores',
                onPressed: _showBookmarks,
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
              const VerticalDivider(width: 20),
              _CommandButton(
                icon: Icons.draw_outlined,
                label: 'Anotar',
                onPressed: _openAnnotations,
              ),
              _CommandButton(
                icon: Icons.edit_document,
                label: 'Páginas',
                onPressed: _openPageTools,
              ),
              _CommandButton(
                icon: Icons.document_scanner_outlined,
                label: 'OCR',
                onPressed: _openOcr,
              ),
              const VerticalDivider(width: 20),
              IconButton(
                tooltip: 'Zoom -',
                onPressed: _zoomOut,
                icon: const Icon(Icons.zoom_out),
              ),
              _buildZoomMenu(),
              IconButton(
                tooltip: 'Zoom +',
                onPressed: _zoomIn,
                icon: const Icon(Icons.zoom_in),
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
              PopupMenuButton<_WorkspaceMoreAction>(
                tooltip: 'Mais ferramentas',
                onSelected: _handleMoreAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _WorkspaceMoreAction.forms,
                    child: ListTile(
                      leading: Icon(Icons.checklist_outlined),
                      title: Text('Formulários'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _WorkspaceMoreAction.export,
                    child: ListTile(
                      leading: Icon(Icons.ios_share_outlined),
                      title: Text('Exportar PDF'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _WorkspaceMoreAction.print,
                    child: ListTile(
                      leading: Icon(Icons.print_outlined),
                      title: Text('Imprimir'),
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomMenu({bool compact = false}) {
    return PopupMenuButton<int>(
      tooltip: 'Definir zoom',
      onSelected: (value) {
        if (value == -1) {
          unawaited(_showCustomZoomDialog());
        } else {
          unawaited(_setZoomPercent(value));
        }
      },
      itemBuilder: (context) => [
        for (final value in _zoomPresets)
          PopupMenuItem(
            value: value,
            child: Text('$value%'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: -1,
          child: Text('Personalizado…'),
        ),
      ],
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 56 : 68),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_zoomPercent%'),
            if (!compact) ...[
              const SizedBox(width: 3),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  void _syncZoomFromController() {
    if (!_controller.isReady) return;
    final percent = (_controller.currentZoom * 100).round();
    if (!mounted || percent == _zoomPercent) return;
    setState(() => _zoomPercent = percent);
  }

  Future<void> _setZoomPercent(int percent) async {
    if (!_controller.isReady) return;
    final target = (percent / 100).clamp(
      _controller.minScale,
      _controller.maxScale,
    );
    await _controller.setZoom(_controller.centerPosition, target);
    _syncZoomFromController();
  }

  Future<void> _showCustomZoomDialog() async {
    final input = TextEditingController(text: '$_zoomPercent');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zoom personalizado'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Zoom (%)',
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              int.tryParse(input.text.trim()),
            ),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || value <= 0) return;
    await _setZoomPercent(value);
  }

  Future<void> _zoomIn() async {
    if (!_controller.isReady) return;
    await _controller.zoomUp();
    _syncZoomFromController();
  }

  Future<void> _zoomOut() async {
    if (!_controller.isReady) return;
    await _controller.zoomDown();
    _syncZoomFromController();
  }

  Future<void> _previousPage() async {
    if (!_controller.isReady || _page <= 1) return;
    await _controller.goToPage(
      pageNumber: _page - 1,
      anchor: PdfPageAnchor.top,
    );
  }

  Future<void> _nextPage() async {
    if (!_controller.isReady) return;
    final count = _document?.pages.length ?? _controller.pageCount;
    if (_page >= count) return;
    await _controller.goToPage(
      pageNumber: _page + 1,
      anchor: PdfPageAnchor.top,
    );
  }

  Future<void> _scrollBy(double deltaY) async {
    if (!_controller.isReady) return;
    final matrix = _controller.value.clone()
      ..multiply(Matrix4.translationValues(0.0, deltaY, 0.0));
    final safe = _controller.makeMatrixInSafeRange(matrix, forceClamp: true);
    await _controller.goTo(
      safe,
      duration: const Duration(milliseconds: 90),
    );
  }

  Future<void> _openAnnotations() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfAdvancedAnnotationScreen(
          document: widget.document,
          annotations: widget.annotations,
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

  Future<void> _openOcr() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfOcrScreen(
          document: widget.document,
          navigationStore: widget.store,
        ),
      ),
    );
  }

  void _handleMoreAction(_WorkspaceMoreAction action) {
    switch (action) {
      case _WorkspaceMoreAction.forms:
        unawaited(_openForms());
      case _WorkspaceMoreAction.export:
        unawaited(_openExport());
      case _WorkspaceMoreAction.print:
        unawaited(_openPrint());
    }
  }

  Future<void> _openForms() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfFormsScreen(
          document: widget.document,
          store: LocalPdfFormStore(widget.store.db),
        ),
      ),
    );
  }

  Future<void> _openExport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfExportScreen(
          document: widget.document,
          db: widget.store.db,
        ),
      ),
    );
  }

  Future<void> _openPrint() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPrintScreen(
          document: widget.document,
          navigationStore: widget.store,
        ),
      ),
    );
  }

  Future<void> _openExternalLink(Uri uri) async {
    if (!mounted) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http' && scheme != 'mailto') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link bloqueado por segurança: $scheme')),
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abrir link externo?'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
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
    await _controller.goToPage(
      pageNumber: target,
      anchor: PdfPageAnchor.top,
    );
    if (mounted) setState(() {});
  }

  Future<void> _goForward() async {
    if (_forwardHistory.isEmpty) return;
    final target = _forwardHistory.removeLast();
    _backHistory.add(_page);
    _historyNavigation = true;
    await _controller.goToPage(
      pageNumber: target,
      anchor: PdfPageAnchor.top,
    );
    if (mounted) setState(() {});
  }

  Future<void> _jumpToPage() async {
    final input = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir para página'),
        content: TextField(
          controller: input,
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
            onPressed: () => Navigator.of(context).pop(
              int.tryParse(input.text),
            ),
            child: const Text('Ir'),
          ),
        ],
      ),
    );
    input.dispose();
    if (page == null || page < 1) return;
    final maxPage = _document?.pages.length;
    if (maxPage != null && page > maxPage) return;
    await _controller.goToPage(
      pageNumber: page,
      anchor: PdfPageAnchor.top,
    );
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
                      unawaited(
                        _controller.goToPage(
                          pageNumber: bookmark.pageNumber,
                          anchor: PdfPageAnchor.top,
                        ),
                      );
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
        contentPadding: EdgeInsets.only(
          left: 12.0 + depth * 18,
          right: 8,
        ),
        title: Text(node.title),
        subtitle:
            node.dest == null ? null : Text('Página ${node.dest!.pageNumber}'),
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
      subtitle:
          node.dest == null ? null : Text('Página ${node.dest!.pageNumber}'),
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
              if (document == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final count = document.pages.length;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
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
                      unawaited(
                        _controller.goToPage(
                          pageNumber: pageNumber,
                          anchor: PdfPageAnchor.top,
                        ),
                      );
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

  PdfPageLayout _horizontalLayout(
    List<PdfPage> pages,
    PdfViewerParams params,
  ) {
    final height = pages.fold<double>(
          0,
          (previous, page) => math.max(previous, page.height),
        ) +
        params.margin * 2;
    final layouts = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      layouts.add(
        Rect.fromLTWH(
          x,
          (height - page.height) / 2,
          page.width,
          page.height,
        ),
      );
      x += page.width + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(x, height),
    );
  }

  PdfPageLayout _facingLayout(
    List<PdfPage> pages,
    PdfViewerParams params,
  ) {
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
      layouts.add(
        Rect.fromLTWH(
          params.margin + maxWidth - left.width,
          y + (rowHeight - left.height) / 2,
          left.width,
          left.height,
        ),
      );
      if (right != null) {
        layouts.add(
          Rect.fromLTWH(
            params.margin * 2 + maxWidth,
            y + (rowHeight - right.height) / 2,
            right.width,
            right.height,
          ),
        );
      }
      y += rowHeight + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(params.margin * 3 + maxWidth * 2, y),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

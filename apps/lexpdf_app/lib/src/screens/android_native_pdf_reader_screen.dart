import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../core/documents/document_provider.dart';

/// Android-only safety reader backed by pdfx/Android PdfRenderer.
///
/// This intentionally starts with a minimal feature set: one native Android
/// renderer, one document, one visible page flow, and no pdfrx/PDFium, OCR,
/// text extraction, outline traversal or annotation hydration in the opening
/// path. Feature layers can be reintroduced only after physical-device
/// stability is proven with large/complex PDFs.
class AndroidNativePdfReaderScreen extends StatefulWidget {
  const AndroidNativePdfReaderScreen({
    required this.document,
    required this.initialPage,
    required this.onPageChanged,
    required this.fullScreen,
    required this.onToggleFullScreen,
    super.key,
  });

  final DocumentRef document;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final bool fullScreen;
  final VoidCallback onToggleFullScreen;

  @override
  State<AndroidNativePdfReaderScreen> createState() =>
      _AndroidNativePdfReaderScreenState();
}

class _AndroidNativePdfReaderScreenState
    extends State<AndroidNativePdfReaderScreen> {
  PdfController? _controller;
  int _page = 1;
  int? _pageCount;
  Object? _openError;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage < 1 ? 1 : widget.initialPage;
    _open();
  }

  void _open() {
    final path = widget.document.localPath;
    if (path == null || path.trim().isEmpty) {
      _openError = StateError('O PDF precisa estar disponível offline.');
      return;
    }

    _controller = PdfController(
      document: PdfDocument.openFile(path),
      initialPage: _page,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _previousPage() async {
    final controller = _controller;
    if (controller == null || _page <= 1) return;
    await controller.previousPage(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  Future<void> _nextPage() async {
    final controller = _controller;
    if (controller == null) return;
    final total = _pageCount;
    if (total != null && _page >= total) return;
    await controller.nextPage(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_openError != null || controller == null) {
      return _AndroidPdfError(
        error: _openError ?? StateError('Não foi possível preparar o PDF.'),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onToggleFullScreen,
            child: PdfView(
              controller: controller,
              scrollDirection: Axis.vertical,
              pageSnapping: true,
              onDocumentLoaded: (document) {
                if (!mounted) return;
                setState(() => _pageCount = document.pagesCount);
              },
              onDocumentError: (error) {
                if (!mounted) return;
                setState(() => _openError = error);
              },
              onPageChanged: (page) {
                if (!mounted) return;
                setState(() => _page = page);
                widget.onPageChanged(page);
              },
            ),
          ),
        ),
        if (!widget.fullScreen)
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: _AndroidPdfNavigationPill(
                page: _page,
                pageCount: _pageCount,
                onPrevious: _page > 1 ? _previousPage : null,
                onNext: _pageCount == null || _page < _pageCount!
                    ? _nextPage
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _AndroidPdfNavigationPill extends StatelessWidget {
  const _AndroidPdfNavigationPill({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int? pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Página anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              pageCount == null ? '$_pageLabel' : '$page / $pageCount',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'Próxima página',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  String get _pageLabel => '$page';
}

class _AndroidPdfError extends StatelessWidget {
  const _AndroidPdfError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 54),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível abrir este PDF no leitor nativo Android.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

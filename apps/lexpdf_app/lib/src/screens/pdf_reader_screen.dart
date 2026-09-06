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
  int? _currentPage;

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
        title: Text(
          widget.document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_currentPage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('Pág. $_currentPage')),
            ),
          IconButton(
            tooltip: 'Pesquisar no PDF',
            onPressed: null,
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
        ],
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
              initialPageNumber: initialPage,
              params: PdfViewerParams(
                textSelectionParams:
                    const PdfTextSelectionParams(enabled: true),
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
}

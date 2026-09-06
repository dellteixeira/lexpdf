import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';

class PdfReaderScreen extends StatelessWidget {
  const PdfReaderScreen({
    required this.document,
    super.key,
  });

  final DocumentRef document;

  @override
  Widget build(BuildContext context) {
    final path = document.localPath;
    if (path == null || path.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(document.name)),
        body: const Center(
          child: Text('Este documento ainda não está disponível offline.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
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
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: PdfViewer.file(
          path,
          params: const PdfViewerParams(
            textSelectionParams: PdfTextSelectionParams(enabled: true),
          ),
        ),
      ),
    );
  }
}

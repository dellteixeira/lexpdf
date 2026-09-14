import 'package:flutter/material.dart';

import '../core/documents/document_provider.dart';
import '../core/pdf/windows_pdf_compat_normalizer.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import 'pdf_workspace_stylus_screen.dart' as stylus;

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
  static const WindowsPdfCompatNormalizer _normalizer =
      WindowsPdfCompatNormalizer();

  late Future<WindowsPdfCompatResult> _prepared;

  @override
  void initState() {
    super.initState();
    _prepared = _prepare();
  }

  Future<WindowsPdfCompatResult> _prepare() async {
    final path = widget.document.localPath;
    if (path == null || path.trim().isEmpty) {
      return const WindowsPdfCompatResult(
        path: '',
        normalized: false,
        reason: 'no-local-path',
      );
    }
    return _normalizer.prepare(path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WindowsPdfCompatResult>(
      future: _prepared,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('PDF')),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparando PDF para renderização...'),
                ],
              ),
            ),
          );
        }

        final result = snapshot.data ?? WindowsPdfCompatResult(
          path: widget.document.localPath ?? '',
          normalized: false,
          reason: 'prepare-failed',
        );
        final originalPath = widget.document.localPath;
        final effectiveDocument = result.normalized &&
                originalPath != null &&
                result.path.isNotEmpty
            ? widget.document.copyWith(localPath: result.path)
            : widget.document;

        return Stack(
          children: [
            stylus.PdfWorkspaceScreen(
              document: effectiveDocument,
              store: widget.store,
              annotations: widget.annotations,
              initialPage: widget.initialPage,
            ),
            if (result.normalized)
              const Positioned(
                left: 12,
                bottom: 12,
                child: IgnorePointer(
                  child: Material(
                    color: Color(0xCC111827),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        'PDF compatível',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

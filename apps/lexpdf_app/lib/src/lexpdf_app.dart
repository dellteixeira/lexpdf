import 'package:flutter/material.dart';

import 'core/documents/document_picker_service.dart';
import 'core/storage/local_database.dart';
import 'core/storage/local_document_catalog.dart';
import 'core/storage/local_ink_store.dart';
import 'core/storage/local_pdf_ink_store.dart';
import 'core/storage/local_pdf_navigation_store.dart';
import 'core/storage/local_reading_progress_store.dart';
import 'core/storage/local_text_annotation_store.dart';
import 'core/theme/lexpdf_theme.dart';
import 'screens/account_screen.dart';
import 'screens/library_screen.dart';
import 'screens/pdf_print_screen.dart';

class LexPdfApp extends StatefulWidget {
  const LexPdfApp({
    required this.database,
    super.key,
  });

  final LocalDatabase database;

  @override
  State<LexPdfApp> createState() => _LexPdfAppState();
}

class _LexPdfAppState extends State<LexPdfApp> {
  late final LocalDocumentCatalog _catalog = LocalDocumentCatalog(widget.database);
  late final LocalReadingProgressStore _readingProgress =
      LocalReadingProgressStore(widget.database);
  late final LocalTextAnnotationStore _annotations =
      LocalTextAnnotationStore(widget.database);
  late final LocalInkStore _inkStore = LocalInkStore(widget.database);
  late final LocalPdfInkStore _pdfInkStore = LocalPdfInkStore(widget.database);
  late final LocalPdfNavigationStore _navigationStore =
      LocalPdfNavigationStore(widget.database);
  final DocumentPickerService _picker = const DocumentPickerService();
  bool _openingPrint = false;

  @override
  void dispose() {
    widget.database.close();
    super.dispose();
  }

  Future<void> _openPrint(BuildContext context) async {
    if (_openingPrint) return;
    setState(() => _openingPrint = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null) return;
      await _catalog.upsert(picked);
      final document = await _catalog.getById(picked.id) ?? picked;
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPrintScreen(
            document: document,
            navigationStore: _navigationStore,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a impressão: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingPrint = false);
    }
  }

  Future<void> _openAccount(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountScreen(database: widget.database),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LexPDF',
      theme: LexPdfTheme.light,
      darkTheme: LexPdfTheme.dark,
      home: Builder(
        builder: (context) => Stack(
          children: [
            LibraryScreen(
              catalog: _catalog,
              readingProgress: _readingProgress,
              annotations: _annotations,
              inkStore: _inkStore,
              pdfInkStore: _pdfInkStore,
            ),
            Positioned(
              right: 20,
              bottom: 86,
              child: SafeArea(
                child: Tooltip(
                  message: 'Conta LexPDF',
                  child: FloatingActionButton.small(
                    heroTag: 'lexpdf-account',
                    onPressed: () => _openAccount(context),
                    child: const Icon(Icons.person_outline),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: SafeArea(
                child: Tooltip(
                  message: 'Imprimir PDF',
                  child: FloatingActionButton.extended(
                    heroTag: 'lexpdf-print',
                    onPressed: _openingPrint ? null : () => _openPrint(context),
                    icon: _openingPrint
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: const Text('Imprimir PDF'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

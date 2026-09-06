import 'package:flutter/material.dart';

import 'core/storage/local_database.dart';
import 'core/storage/local_document_catalog.dart';
import 'core/storage/local_ink_store.dart';
import 'core/storage/local_pdf_ink_store.dart';
import 'core/storage/local_reading_progress_store.dart';
import 'core/storage/local_text_annotation_store.dart';
import 'screens/library_screen.dart';

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

  @override
  void dispose() {
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LexPDF',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF246BFD),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6EA0FF),
        brightness: Brightness.dark,
      ),
      home: LibraryScreen(
        catalog: _catalog,
        readingProgress: _readingProgress,
        annotations: _annotations,
        inkStore: _inkStore,
        pdfInkStore: _pdfInkStore,
      ),
    );
  }
}

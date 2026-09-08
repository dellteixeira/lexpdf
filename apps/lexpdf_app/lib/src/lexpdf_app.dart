import 'dart:io';

import 'package:flutter/material.dart';

import 'core/documents/document_picker_service.dart';
import 'core/documents/document_provider.dart';
import 'core/documents/native_pdf_open_service.dart';
import 'core/storage/local_database.dart';
import 'core/storage/local_document_catalog.dart';
import 'core/storage/local_ink_store.dart';
import 'core/storage/local_pdf_ink_store.dart';
import 'core/storage/local_pdf_navigation_store.dart';
import 'core/storage/local_reading_progress_store.dart';
import 'core/storage/local_text_annotation_store.dart';
import 'core/theme/lexpdf_theme.dart';
import 'screens/account_screen.dart';
import 'screens/minimal_library_sections_screen.dart';
import 'screens/pdf_print_screen.dart';
import 'screens/pdf_reader_screen.dart';

class LexPdfApp extends StatefulWidget {
  const LexPdfApp({
    required this.database,
    this.initialPdfPath,
    super.key,
  });

  final LocalDatabase database;
  final String? initialPdfPath;

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
  final NativePdfOpenService _nativeOpen = NativePdfOpenService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _openingPrint = false;
  String? _lastNativePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapNativeOpen());
  }

  Future<void> _bootstrapNativeOpen() async {
    final initialPath = widget.initialPdfPath;
    if (initialPath != null) await _openNativePdf(initialPath);
    await _nativeOpen.start(_openNativePdf);
  }

  Future<void> _openNativePdf(String path) async {
    if (!mounted || _lastNativePath == path) return;
    _lastNativePath = path;

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('arquivo não encontrado');
      }
      if (!path.toLowerCase().endsWith('.pdf')) {
        throw StateError('arquivo recebido não é PDF');
      }

      final document = DocumentRef(
        id: path,
        name: path.split(Platform.pathSeparator).last,
        provider: DocumentProviderKind.local,
        localPath: path,
        availableOffline: true,
        syncState: DocumentSyncState.localOnly,
      );
      await _catalog.upsert(document);
      await _catalog.markOpened(document.id);
      final stored = await _catalog.getById(document.id) ?? document;
      final navigator = _navigatorKey.currentState;
      if (!mounted || navigator == null) return;

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PdfReaderScreen(
            document: stored,
            readingProgress: _readingProgress,
            annotations: _annotations,
            pdfInkStore: _pdfInkStore,
          ),
        ),
      );
    } catch (error) {
      _lastNativePath = null;
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o PDF recebido: $error')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nativeOpen.dispose();
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
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'LexPDF',
      theme: LexPdfTheme.light,
      darkTheme: LexPdfTheme.dark,
      home: Builder(
        builder: (context) => MinimalLibrarySectionsScreen(
          catalog: _catalog,
          readingProgress: _readingProgress,
          annotations: _annotations,
          inkStore: _inkStore,
          pdfInkStore: _pdfInkStore,
          onOpenAccount: () => _openAccount(context),
          onOpenPrint: () => _openPrint(context),
        ),
      ),
    );
  }
}

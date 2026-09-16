import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core/documents/document_picker_service.dart';
import 'core/documents/document_provider.dart';
import 'core/documents/native_pdf_open_service.dart';
import 'core/storage/local_database.dart';
import 'core/storage/local_document_catalog.dart';
import 'core/storage/local_ink_store.dart';
import 'core/storage/local_pdf_navigation_store.dart';
import 'core/storage/local_pdf_workspace_session_store.dart';
import 'core/storage/local_text_annotation_store.dart';
import 'core/theme/lexpdf_theme.dart';
import 'screens/account_screen.dart';
import 'screens/library_workspace_home_screen.dart';
import 'screens/pdf_print_screen.dart';
import 'screens/pdf_workspace_screen.dart';

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
  late final LocalTextAnnotationStore _annotations =
      LocalTextAnnotationStore(widget.database);
  late final LocalInkStore _inkStore = LocalInkStore(widget.database);
  late final LocalPdfNavigationStore _navigationStore =
      LocalPdfNavigationStore(widget.database);
  late final LocalPdfWorkspaceSessionStore _workspaceSessionStore =
      LocalPdfWorkspaceSessionStore(widget.database);
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
    await _nativeOpen.start(
      _openNativePdf,
      onOpenMany: _openNativePdfBatch,
    );
  }

  Future<void> _openNativePdf(String path) => _openNativePdfBatch([path]);

  Future<void> _openNativePdfBatch(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final requested = paths.toSet().take(10).toList(growable: false);
    if (requested.isEmpty || _lastNativePath == requested.first) return;
    _lastNativePath = requested.first;

    try {
      final documents = <DocumentRef>[];
      for (final path in requested) {
        final file = File(path);
        if (!await file.exists()) continue;
        if (!path.toLowerCase().endsWith('.pdf')) continue;
        final document = DocumentRef(
          id: path,
          name: path.split(Platform.pathSeparator).last,
          provider: DocumentProviderKind.local,
          localPath: path,
          availableOffline: true,
          syncState: DocumentSyncState.localOnly,
        );
        await _catalog.upsert(document);
        documents.add(document);
      }
      if (documents.isEmpty) {
        throw StateError('nenhum PDF válido foi recebido');
      }

      // Windows drag/drop may deliver several PDFs at once. Merge them into the
      // persistent workspace session before opening the shell so they appear as
      // real tabs instead of spawning several application windows/routes.
      final current = await _workspaceSessionStore.load();
      final merged = <PdfWorkspaceTabState>[];
      final seen = <String>{};
      for (final tab in current.tabs) {
        if (seen.add(tab.document.id)) merged.add(tab);
      }
      for (final document in documents) {
        if (seen.add(document.id)) {
          merged.add(PdfWorkspaceTabState(document: document, initialPage: 1));
        }
      }
      while (merged.length > 10) {
        merged.removeAt(0);
      }
      final active = documents.first;
      await _workspaceSessionStore.save(
        tabs: merged,
        activeDocumentId: active.id,
      );

      final navigator = _navigatorKey.currentState;
      if (!mounted || navigator == null) return;
      unawaited(_catalog.markOpened(active.id));
      try {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PdfWorkspaceScreen(
              document: active,
              store: _navigationStore,
              annotations: _annotations,
            ),
          ),
        );
      } finally {
        if (_lastNativePath == active.localPath) _lastNativePath = null;
      }
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
        builder: (context) => LibraryWorkspaceHomeScreen(
          catalog: _catalog,
          annotations: _annotations,
          inkStore: _inkStore,
          onOpenAccount: () => _openAccount(context),
          onOpenPrint: () => _openPrint(context),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/ai/ai_access_session.dart';
import '../core/ai/pdf_page_vision_rasterizer.dart';
import '../core/ai/remote_vision_service.dart';
import '../core/backend/backend_config.dart';
import '../core/documents/document_picker_service.dart';
import '../core/documents/document_provider.dart';
import '../core/ocr/mobile_pdf_ocr_service.dart';
import '../core/platform/workspace_full_screen_service.dart';
import '../core/pdf/huge_pdf_policy.dart';
import '../core/storage/local_advanced_study_store.dart';
import '../core/storage/local_document_catalog.dart';
import '../core/storage/local_knowledge_rag_store.dart';
import '../core/storage/local_ocr_store.dart';
import '../core/storage/local_pdf_ink_store.dart';
import '../core/storage/local_pdf_navigation_store.dart';
import '../core/storage/local_pdf_workspace_session_store.dart';
import '../core/storage/local_reading_progress_store.dart';
import '../core/storage/local_text_annotation_store.dart';
import '../core/storage/local_workspace_ui_preferences.dart';
import 'ai_context_chat_screen.dart';
import 'android_apryse_pdf_reader_screen.dart';
import 'flashcard_center_screen.dart';
import 'pdf_workspace_stylus_screen.dart' as editor;

/// Persistent multi-document shell for the unified PDF editor.
///
/// Every tab owns its own editor State through an IndexedStack, so switching
/// documents does not destroy the active PDF viewer. Desktop may index while
/// idle; Android indexing/OCR is strictly user-triggered so PDFium owns the
/// reading critical path without competing native raster work.
/// Phase 7 keeps productivity chrome outside the editor so stylus, touch,
/// selection, rendering and annotation input contracts remain isolated.
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

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen>
    with WidgetsBindingObserver {
  static const int _maxTabs = 10;
  static const double _sidePanelBreakpoint = 760;
  static const double _desktopMenuBreakpoint = 920;

  final DocumentPickerService _picker = const DocumentPickerService();
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'pdf-tab-shell');
  final List<_WorkspaceTab> _tabs = <_WorkspaceTab>[];
  final Map<String, _WorkspaceOcrTask> _ocrTasks = <String, _WorkspaceOcrTask>{};
  final Set<String> _autoIndexInspected = <String>{};
  final WorkspaceFullScreenService _fullScreenService =
      const WorkspaceFullScreenService();

  late final LocalPdfWorkspaceSessionStore _sessionStore =
      LocalPdfWorkspaceSessionStore(widget.store.db);
  late final LocalPdfInkStore _inkStore = LocalPdfInkStore(widget.store.db);
  late final LocalReadingProgressStore _progressStore =
      LocalReadingProgressStore(widget.store.db);
  late final LocalOcrStore _ocrStore = LocalOcrStore(widget.store.db);
  late final LocalWorkspaceUiPreferences _uiPreferences =
      LocalWorkspaceUiPreferences(widget.store.db);
  late final MobilePdfOcrService _ocrService = MobilePdfOcrService(
    ocrStore: _ocrStore,
    navigationStore: widget.store,
  );

  int _activeIndex = 0;
  bool _restoring = true;
  bool _picking = false;
  bool _panelVisible = true;
  bool _statusBarVisible = true;
  bool _denseToolbar = false;
  bool _visionAnalyzing = false;
  bool _fullScreen = false;
  Timer? _idleIndexTimer;
  int _readerActivityEpoch = 0;
  DateTime? _lastReaderActivityAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uiPreferences.ensureSchema();
    _panelVisible = _uiPreferences.readBool(
      LocalWorkspaceUiPreferences.panelVisibleKey,
      fallback: true,
    );
    _statusBarVisible = _uiPreferences.readBool(
      LocalWorkspaceUiPreferences.statusBarVisibleKey,
      fallback: true,
    );
    _denseToolbar = _uiPreferences.readBool(
      LocalWorkspaceUiPreferences.denseToolbarKey,
      fallback: false,
    );
    _tabs.add(
      _WorkspaceTab(
        document: widget.document,
        initialPage: widget.initialPage < 1 ? 1 : widget.initialPage,
      ),
    );
    unawaited(_restoreSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_saveSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleIndexTimer?.cancel();
    for (final task in _ocrTasks.values) {
      task.cancelRequested = true;
    }
    unawaited(_saveSession());
    if (_fullScreen) {
      unawaited(_fullScreenService.setEnabled(false));
    }
    _shortcutFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final saved = await _sessionStore.load();
      final restored = <_WorkspaceTab>[];
      final seen = <String>{};

      for (final savedTab in saved.tabs) {
        final path = savedTab.document.localPath;
        if (path == null || path.isEmpty || !File(path).existsSync()) continue;
        if (!seen.add(savedTab.document.id)) continue;
        final progress = await _progressStore.get(savedTab.document.id);
        restored.add(
          _WorkspaceTab(
            document: savedTab.document,
            initialPage: progress?.pageNumber ?? savedTab.initialPage,
          ),
        );
        if (restored.length >= _maxTabs) break;
      }

      final incomingIndex = restored.indexWhere(
        (tab) => tab.document.id == widget.document.id,
      );
      if (incomingIndex < 0) {
        if (restored.length >= _maxTabs) restored.removeAt(0);
        restored.add(
          _WorkspaceTab(
            document: widget.document,
            initialPage: widget.initialPage < 1 ? 1 : widget.initialPage,
          ),
        );
      }

      final active = restored.indexWhere(
        (tab) => tab.document.id == widget.document.id,
      );
      if (!mounted) return;
      setState(() {
        _tabs
          ..clear()
          ..addAll(restored);
        _activeIndex = active < 0 ? 0 : active;
        _restoring = false;
      });
      await _saveSession();
    } catch (_) {
      if (!mounted) return;
      setState(() => _restoring = false);
    }
  }

  Future<void> _saveSession() async {
    if (_tabs.isEmpty) {
      await _sessionStore.clear();
      return;
    }
    final safeIndex = _activeIndex.clamp(0, _tabs.length - 1).toInt();
    await _sessionStore.save(
      tabs: [
        for (final tab in _tabs)
          PdfWorkspaceTabState(
            document: tab.document,
            initialPage: tab.initialPage,
          ),
      ],
      activeDocumentId: _tabs[safeIndex].document.id,
    );
  }

  Future<void> _openAnotherPdf() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickPdf();
      if (picked == null || !mounted) return;
      final existing = _tabs.indexWhere((tab) => tab.document.id == picked.id);
      if (existing >= 0) {
        setState(() => _activeIndex = existing);
        await _saveSession();
        return;
      }
      if (_tabs.length >= _maxTabs) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feche uma aba antes de abrir outro PDF (limite: 10).'),
          ),
        );
        return;
      }
      setState(() {
        _tabs.add(_WorkspaceTab(document: picked, initialPage: 1));
        _activeIndex = _tabs.length - 1;
      });
      await _saveSession();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isNotEmpty) {
        if (_activeIndex > index) {
          _activeIndex--;
        } else if (_activeIndex >= _tabs.length) {
          _activeIndex = _tabs.length - 1;
        }
      }
    });
    if (_tabs.isEmpty) {
      await _sessionStore.clear();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await _saveSession();
  }

  Future<void> _closeActiveTab() async {
    if (_tabs.isEmpty) return;
    await _closeTab(_activeIndex);
  }

  Future<void> _activateTab(int index) async {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    setState(() => _activeIndex = index);
    await _saveSession();
    final tab = _tabs[index];
    if (tab.viewerDocument != null) {
      unawaited(_inspectActiveDocumentForIndexing(tab));
    }
  }

  Future<void> _undo() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final result = await _inkStore.undo(tab.document.id);
    if (!mounted) return;
    if (!result.changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para desfazer neste PDF.')),
      );
      return;
    }
    setState(() {
      tab.initialPage = result.pageNumber;
      tab.generation += 1;
    });
    await _saveSession();
  }

  Future<void> _redo() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final result = await _inkStore.redo(tab.document.id);
    if (!mounted) return;
    if (!result.changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para refazer neste PDF.')),
      );
      return;
    }
    setState(() {
      tab.initialPage = result.pageNumber;
      tab.generation += 1;
    });
    await _saveSession();
  }

  void _onViewerDocumentChanged(
    _WorkspaceTab tab,
    PdfDocument? viewerDocument,
  ) {
    tab.viewerDocument = viewerDocument;
    if (viewerDocument == null) {
      tab.pageCount = null;
      tab.localizedIndexPending = false;
      final task = _ocrTasks[tab.document.id];
      if (task?.automatic == true) {
        task!.cancelRequested = true;
      }
      return;
    }

    tab.pageCount = viewerDocument.pages.length;
    if (Platform.isAndroid) {
      // Reader-first Android contract: opening a PDF must never implicitly
      // trigger text extraction, raster OCR or FTS work. Search/OCR can still
      // invoke _startBackgroundIndexing after an explicit user action.
      tab.localizedIndexPending = false;
      _idleIndexTimer?.cancel();
      for (final task in _ocrTasks.values) {
        if (task.running && task.automatic) {
          task.cancelRequested = true;
        }
      }
      return;
    }

    if (_tabs.isNotEmpty &&
        _activeIndex >= 0 &&
        _activeIndex < _tabs.length &&
        identical(_tabs[_activeIndex], tab)) {
      _lastReaderActivityAt = DateTime.now();
      unawaited(_inspectActiveDocumentForIndexing(tab));
    }
  }

  Future<void> _inspectActiveDocumentForIndexing(_WorkspaceTab tab) async {
    if (Platform.isAndroid) return;
    if (!mounted || _tabs.isEmpty) return;
    if (_activeIndex < 0 || _activeIndex >= _tabs.length) return;
    if (!identical(_tabs[_activeIndex], tab)) return;

    final viewerDocument = tab.viewerDocument;
    final pageCount = tab.pageCount;
    if (viewerDocument == null || pageCount == null || pageCount <= 0) return;
    if (_ocrTasks[tab.document.id]?.running == true) return;

    try {
      final complete = await _ocrStore.hasCompleteDocumentIndex(
        tab.document.id,
        pageCount: pageCount,
        acceptedEngines: _ocrService.resumeEngines,
      );
      if (complete) return;
      if (!_autoIndexInspected.add(tab.document.id)) return;
      if (!mounted ||
          _tabs.isEmpty ||
          _activeIndex < 0 ||
          _activeIndex >= _tabs.length ||
          !identical(_tabs[_activeIndex], tab) ||
          !identical(tab.viewerDocument, viewerDocument)) {
        return;
      }

      // Reader-first: no second PdfDocument is opened merely to inspect/index
      // the file. Automatic indexing reuses the exact document already owned
      // by the visible viewer and waits until rendering has been idle.
      tab.localizedIndexPending = true;
      _scheduleIdleIndexContinuation(tab);
    } catch (_) {
      // Index scheduling is advisory; reading must never depend on it.
    }
  }

  void _markReaderActivity(_WorkspaceTab tab) {
    if (!mounted || _tabs.isEmpty) return;
    if (_activeIndex < 0 || _activeIndex >= _tabs.length) return;
    if (!identical(_tabs[_activeIndex], tab)) return;

    _readerActivityEpoch++;
    _lastReaderActivityAt = DateTime.now();
    _idleIndexTimer?.cancel();
    for (final task in _ocrTasks.values) {
      if (task.running && task.automatic) {
        task.cancelRequested = true;
      }
    }
    if (!Platform.isAndroid) {
      _scheduleIdleIndexContinuation(tab);
    }
  }

  void _scheduleIdleIndexContinuation(_WorkspaceTab tab) {
    _idleIndexTimer?.cancel();
    if (Platform.isAndroid) return;
    if (tab.viewerDocument == null) return;
    final scheduledEpoch = _readerActivityEpoch;
    _idleIndexTimer = Timer(HugePdfPolicy.backgroundIndexIdleDelay, () {
      if (!mounted || _tabs.isEmpty) return;
      if (_activeIndex < 0 || _activeIndex >= _tabs.length) return;
      if (!identical(_tabs[_activeIndex], tab)) return;
      if (scheduledEpoch != _readerActivityEpoch) return;

      final lastActivity = _lastReaderActivityAt;
      if (lastActivity != null) {
        final quietFor = DateTime.now().difference(lastActivity);
        if (quietFor < HugePdfPolicy.backgroundIndexIdleDelay) {
          _scheduleIdleIndexContinuation(tab);
          return;
        }
      }
      unawaited(_continueIndexingWhenIdle(tab, scheduledEpoch));
    });
  }

  Future<void> _continueIndexingWhenIdle(
    _WorkspaceTab tab,
    int scheduledEpoch,
  ) async {
    if (Platform.isAndroid) return;
    if (!mounted || _tabs.isEmpty) return;
    if (_activeIndex < 0 || _activeIndex >= _tabs.length) return;
    if (!identical(_tabs[_activeIndex], tab)) return;
    if (scheduledEpoch != _readerActivityEpoch) return;

    final pageCount = tab.pageCount;
    if (pageCount == null || pageCount <= 0) return;

    final existing = _ocrTasks[tab.document.id];
    if (existing?.running == true) {
      _scheduleIdleIndexContinuation(tab);
      return;
    }

    final processedState = await _ocrStore.processedPageState(
      tab.document.id,
      acceptedEngines: _ocrService.resumeEngines,
    );
    if (!mounted || _tabs.isEmpty) return;
    if (_activeIndex < 0 || _activeIndex >= _tabs.length) return;
    if (!identical(_tabs[_activeIndex], tab)) return;
    if (scheduledEpoch != _readerActivityEpoch) return;

    final processedPages = processedState.keys.toSet();
    final window = tab.localizedIndexPending
        ? HugePdfPolicy.localizedIndexWindow(
            pageNumber: tab.initialPage,
            pageCount: pageCount,
          )
        : HugePdfPolicy.nextIdleIndexWindow(
            pageNumber: tab.initialPage,
            pageCount: pageCount,
            processedPages: processedPages,
          );
    if (window == null || window.end < window.start) {
      tab.localizedIndexPending = false;
      return;
    }

    final completed = await _startIdleIndexChunk(
      tab,
      startPage: window.start,
      endPage: window.end,
    );
    if (completed &&
        mounted &&
        _tabs.isNotEmpty &&
        _activeIndex >= 0 &&
        _activeIndex < _tabs.length &&
        identical(_tabs[_activeIndex], tab) &&
        scheduledEpoch == _readerActivityEpoch) {
      tab.localizedIndexPending = false;
      _scheduleIdleIndexContinuation(tab);
    }
  }

  Future<bool> _startIdleIndexChunk(
    _WorkspaceTab tab, {
    required int startPage,
    required int endPage,
  }) async {
    final document = tab.document;
    final viewerDocument = tab.viewerDocument;
    if (viewerDocument == null) return false;

    final existing = _ocrTasks[document.id];
    if (existing?.running == true) return false;
    final task = existing ?? _WorkspaceOcrTask();
    task
      ..running = true
      ..automatic = true
      ..cancelRequested = false
      ..error = null
      ..summary = null
      ..progress = null;
    _ocrTasks[document.id] = task;

    try {
      final summary = await _ocrService.process(
        documentId: document.id,
        openedDocument: viewerDocument,
        startPage: startPage,
        endPage: endPage,
        resume: true,
        isCancelled: () => task.cancelRequested,
        onProgress: (progress) {
          task.progress = progress;
        },
      );
      task.summary = summary;
      return !summary.cancelled && !task.cancelRequested;
    } catch (error) {
      task.error = error;
      return false;
    } finally {
      task
        ..running = false
        ..automatic = false;
    }
  }

  Future<void> _startBackgroundIndexing(_WorkspaceTab tab) async {
    final document = tab.document;
    final viewerDocument = tab.viewerDocument;
    if (viewerDocument == null) return;
    final existing = _ocrTasks[document.id];
    if (existing?.running == true) return;
    final task = existing ?? _WorkspaceOcrTask();
    task
      ..running = true
      ..automatic = false
      ..cancelRequested = false
      ..error = null
      ..summary = null
      ..progress = null;
    _ocrTasks[document.id] = task;
    try {
      final summary = await _ocrService.process(
        documentId: document.id,
        openedDocument: viewerDocument,
        resume: true,
        isCancelled: () => task.cancelRequested,
        onProgress: (progress) {
          // Silent by design: background indexing must never repaint or cover
          // the document while the user is reading.
          task.progress = progress;
        },
      );
      task.summary = summary;
    } catch (error) {
      // Keep diagnostics internal. Automatic indexing must not interrupt the
      // reading surface with progress cards, snackbars or error banners.
      task.error = error;
    } finally {
      task.running = false;
    }
  }

  void _startActiveIndexing() {
    if (_tabs.isEmpty) return;
    unawaited(_startBackgroundIndexing(_tabs[_activeIndex]));
  }

  void _cancelActiveIndexing() {
    if (_tabs.isEmpty) return;
    final task = _ocrTasks[_tabs[_activeIndex].document.id];
    if (task == null || !task.running) return;
    setState(() => task.cancelRequested = true);
  }

  Future<void> _showDocumentSearch() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeIndex];
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pesquisar no PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Digite uma palavra ou expressão',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Pesquisar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || query == null || query.isEmpty) return;

    final rows = widget.store.db.database.select('''
      SELECT page_number, content
      FROM pdf_page_text_index
      WHERE document_id = ? AND lower(content) LIKE ?
      ORDER BY page_number
      LIMIT 200;
    ''', [tab.document.id, '%${query.toLowerCase()}%']);

    if (!mounted) return;
    if (rows.isEmpty) {
      final hasIndex = widget.store.db.database.select('''
        SELECT 1 FROM pdf_page_text_index WHERE document_id = ? LIMIT 1;
      ''', [tab.document.id]).isNotEmpty;
      if (!hasIndex) {
        unawaited(_startBackgroundIndexing(tab));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasIndex
                ? 'Nenhuma ocorrência de “$query” foi localizada.'
                : 'A indexação deste PDF foi iniciada para atender à busca. '
                    'Tente novamente em alguns instantes.',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.70,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final page = row['page_number'] as int;
              final content = row['content'] as String? ?? '';
              return ListTile(
                leading: CircleAvatar(child: Text('$page')),
                title: Text('Página $page'),
                subtitle: Text(
                  _searchSnippet(content, query),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openIndexedSearchPage(page);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _searchSnippet(String content, String query) {
    final lower = content.toLowerCase();
    final index = lower.indexOf(query.toLowerCase());
    if (index < 0) {
      return content.length <= 180 ? content : '${content.substring(0, 180)}…';
    }
    final start = (index - 70).clamp(0, content.length);
    final end = (index + query.length + 100).clamp(0, content.length);
    return '${start > 0 ? '…' : ''}${content.substring(start, end)}${end < content.length ? '…' : ''}';
  }

  void _openIndexedSearchPage(int page) {
    if (_tabs.isEmpty || page < 1) return;
    final tab = _tabs[_activeIndex];
    setState(() {
      tab.initialPage = page;
      tab.generation += 1;
    });
    unawaited(_saveSession());
  }

  void _recordVisiblePage(_WorkspaceTab tab, int pageNumber) {
    _markReaderActivity(tab);
    if (pageNumber < 1 || tab.initialPage == pageNumber) return;
    tab.initialPage = pageNumber;
    unawaited(_saveSession());
  }

  Widget _buildEditorForTab(_WorkspaceTab tab) {
    final key = ValueKey(
      'pdf-tab-${tab.document.id}-${tab.generation}',
    );

    if (Platform.isAndroid) {
      return AndroidAprysePdfReaderScreen(
        key: key,
        document: tab.document,
        fullScreen: _fullScreen,
        onToggleFullScreen: _toggleFullScreen,
      );
    }

    return editor.PdfWorkspaceScreen(
      key: key,
      document: tab.document,
      store: widget.store,
      annotations: widget.annotations,
      initialPage: tab.initialPage,
      fullScreen: _fullScreen,
      showDocumentHeader: false,
      onToggleFullScreen: _toggleFullScreen,
      onPageChanged: (pageNumber) => _recordVisiblePage(tab, pageNumber),
      onReaderActivity: () => _markReaderActivity(tab),
      onViewerDocumentChanged: (document) =>
          _onViewerDocumentChanged(tab, document),
    );
  }

  Widget _buildPdfEditorSurface() {
    if (Platform.isAndroid) {
      // Android PDF rendering is delegated to Apryse DocumentActivity in a
      // dedicated process. No pdfrx/PDFium viewer is mounted by Flutter.
      return _buildEditorForTab(_tabs[_activeIndex]);
    }

    return IndexedStack(
      index: _activeIndex,
      children: [
        for (final tab in _tabs) _buildEditorForTab(tab),
      ],
    );
  }

  void _toggleWorkspacePanel() {
    final value = !_panelVisible;
    setState(() => _panelVisible = value);
    _uiPreferences.writeBool(
      LocalWorkspaceUiPreferences.panelVisibleKey,
      value,
    );
  }

  void _toggleStatusBar() {
    final value = !_statusBarVisible;
    setState(() => _statusBarVisible = value);
    _uiPreferences.writeBool(
      LocalWorkspaceUiPreferences.statusBarVisibleKey,
      value,
    );
  }

  void _toggleDenseToolbar() {
    final value = !_denseToolbar;
    setState(() => _denseToolbar = value);
    _uiPreferences.writeBool(
      LocalWorkspaceUiPreferences.denseToolbarKey,
      value,
    );
  }

  void _toggleFullScreen() {
    unawaited(_setFullScreen(!_fullScreen));
  }

  Future<void> _setFullScreen(bool enabled) async {
    if (!mounted || _fullScreen == enabled) return;
    setState(() => _fullScreen = enabled);
    try {
      await _fullScreenService.setEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _fullScreen = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Não foi possível alterar o modo de tela cheia.'),
        ),
      );
    }
  }

  List<_WorkspaceCommand> _commands() {
    return [
      _WorkspaceCommand(
        label: 'Abrir outro PDF',
        shortcut: 'Ctrl+O',
        icon: Icons.add_box_outlined,
        action: () => unawaited(_openAnotherPdf()),
      ),
      _WorkspaceCommand(
        label: 'Pesquisar no PDF',
        shortcut: 'Ctrl+F',
        icon: Icons.search,
        action: () => unawaited(_showDocumentSearch()),
      ),
      _WorkspaceCommand(
        label: 'Desfazer anotação',
        shortcut: 'Ctrl+Z',
        icon: Icons.undo,
        action: () => unawaited(_undo()),
      ),
      _WorkspaceCommand(
        label: 'Refazer anotação',
        shortcut: 'Ctrl+Y',
        icon: Icons.redo,
        action: () => unawaited(_redo()),
      ),
      _WorkspaceCommand(
        label: _panelVisible ? 'Ocultar painel do workspace' : 'Mostrar painel do workspace',
        shortcut: 'Ctrl+B',
        icon: Icons.view_sidebar_outlined,
        action: _toggleWorkspacePanel,
      ),
      _WorkspaceCommand(
        label: 'Iniciar ou retomar OCR/indexação',
        shortcut: 'Ctrl+Shift+I',
        icon: Icons.document_scanner_outlined,
        action: _startActiveIndexing,
      ),
      _WorkspaceCommand(
        label: 'Fechar aba atual',
        shortcut: 'Ctrl+W',
        icon: Icons.tab_unselected,
        action: () => unawaited(_closeActiveTab()),
      ),
      _WorkspaceCommand(
        label: _fullScreen ? 'Sair da tela cheia' : 'Entrar em tela cheia',
        shortcut: 'F11',
        icon: _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
        action: _toggleFullScreen,
      ),
      _WorkspaceCommand(
        label: _statusBarVisible ? 'Ocultar barra de status' : 'Mostrar barra de status',
        shortcut: '',
        icon: Icons.space_bar,
        action: _toggleStatusBar,
      ),
      _WorkspaceCommand(
        label: _denseToolbar ? 'Usar barra de ferramentas confortável' : 'Usar barra de ferramentas compacta',
        shortcut: '',
        icon: Icons.density_small,
        action: _toggleDenseToolbar,
      ),
      _WorkspaceCommand(
        label: 'Ver atalhos do workspace',
        shortcut: '',
        icon: Icons.keyboard_outlined,
        action: () => unawaited(_showShortcutsHelp()),
      ),
    ];
  }

  Future<void> _showCommandPalette() async {
    final commands = _commands();
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final filtered = normalized.isEmpty
              ? commands
              : commands.where((command) {
                  return command.label.toLowerCase().contains(normalized) ||
                      command.shortcut.toLowerCase().contains(normalized);
                }).toList();
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: const Row(
              children: [
                Icon(Icons.terminal_outlined, size: 20),
                SizedBox(width: 8),
                Text('Paleta de comandos'),
              ],
            ),
            content: SizedBox(
              width: 560,
              height: 430,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Digite uma ação…',
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Nenhum comando encontrado.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final command = filtered[index];
                              return ListTile(
                                leading: Icon(command.icon),
                                title: Text(command.label),
                                trailing: command.shortcut.isEmpty
                                    ? null
                                    : _ShortcutBadge(command.shortcut),
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  command.action();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showShortcutsHelp() {
    const shortcuts = [
      ('Ctrl/Cmd+O', 'Abrir outro PDF'),
      ('Ctrl/Cmd+W', 'Fechar aba atual'),
      ('Ctrl/Cmd+F', 'Pesquisar no PDF'),
      ('Ctrl/Cmd+Z', 'Desfazer'),
      ('Ctrl/Cmd+Y', 'Refazer'),
      ('Ctrl/Cmd+Shift+Z', 'Refazer alternativo'),
      ('Ctrl/Cmd+B', 'Mostrar/ocultar painel'),
      ('Ctrl/Cmd+Shift+I', 'Iniciar/retomar OCR'),
      ('Ctrl/Cmd+Shift+P', 'Paleta de comandos'),
      ('Ctrl/Cmd+H', 'Modo leitura em tela cheia'),
      ('F11', 'Entrar/sair da tela cheia'),
      ('Esc', 'Sair do modo leitura/tela cheia'),
    ];
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Atalhos do workspace'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in shortcuts)
                ListTile(
                  dense: true,
                  title: Text(item.$2),
                  trailing: _ShortcutBadge(item.$1),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeActivePageWithAi() async {
    if (_tabs.isEmpty || _visionAnalyzing) return;
    final tab = _tabs[_activeIndex];
    final document = tab.document;
    final path = document.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O PDF local não está disponível para análise visual.'),
        ),
      );
      return;
    }

    setState(() => _visionAnalyzing = true);
    try {
      const config = BackendConfig.fromEnvironment;
      final token = await AiAccessSession.bearerToken(config: config);
      final progress = await _progressStore.get(document.id);
      final pageNumber = progress?.pageNumber ?? tab.initialPage;
      final image = await const PdfPageVisionRasterizer().rasterize(
        filePath: path,
        pageNumber: pageNumber,
      );
      final base = Uri.parse(config.aiGatewayUrl);
      final result = await RemoteAiVisionService(
        endpoint: base.replace(
          path: '/v1/ai/vision',
          query: null,
          fragment: null,
        ),
        bearerToken: token,
      ).analyze(
        imageBytes: image,
        mimeType: 'image/jpeg',
        prompt:
            'Analise fielmente a página $pageNumber do PDF "${document.name}" '
            'para indexação no LexPDF. Descreva tabelas, gráficos, diagramas, '
            'imagens, manuscritos e relações visuais relevantes. Transcreva '
            'apenas texto visual importante que esteja legível. Não complete '
            'lacunas com conhecimento externo.',
      );
      await LocalKnowledgeRagStore(widget.store.db).upsertVisualDescription(
        id: 'pdf-page:${document.id}:$pageNumber',
        sourceKind: 'pdf_visual',
        ownerId: document.id,
        ownerTitle: 'Visual — ${document.name}',
        pageNumber: pageNumber,
        pdfDocumentId: document.id,
        description: result.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Página $pageNumber analisada visualmente. '
            'A descrição agora participa do RAG.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível analisar a página: $error')),
      );
    } finally {
      if (mounted) setState(() => _visionAnalyzing = false);
    }
  }

  Future<void> _openFlashcardSource(
    String documentId,
    int pageNumber,
  ) async {
    final existing = _tabs.indexWhere(
      (tab) => tab.document.id == documentId,
    );
    if (existing >= 0) {
      setState(() {
        _activeIndex = existing;
        _tabs[existing].initialPage = pageNumber;
        _tabs[existing].generation += 1;
      });
      await _saveSession();
      return;
    }

    final document =
        await LocalDocumentCatalog(widget.store.db).getById(documentId);
    if (!mounted) return;
    if (document == null || !document.hasLocalPath) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O PDF original deste flashcard não está disponível.'),
        ),
      );
      return;
    }
    if (_tabs.length >= _maxTabs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feche uma aba antes de abrir a fonte do flashcard.'),
        ),
      );
      return;
    }
    setState(() {
      _tabs.add(_WorkspaceTab(document: document, initialPage: pageNumber));
      _activeIndex = _tabs.length - 1;
    });
    await _saveSession();
  }

  Future<void> _openFlashcardCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FlashcardCenterScreen(
          store: LocalAdvancedStudyStore(widget.store.db),
          onOpenSource: _openFlashcardSource,
        ),
      ),
    );
  }

  Future<void> _openDocumentChat() async {
    if (_tabs.isEmpty) return;
    final activeDocument = _tabs[_activeIndex].document;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiContextChatScreen(
          database: widget.store.db,
          documentId: activeDocument.id,
          documentTitle: activeDocument.name,
          popAfterSourceOpen: true,
          onOpenSource: (documentId, pageNumber) async {
            final index =
                _tabs.indexWhere((tab) => tab.document.id == documentId);
            if (index < 0 || !mounted) return;
            setState(() {
              _activeIndex = index;
              _tabs[index].initialPage = pageNumber;
              _tabs[index].generation += 1;
            });
            await _saveSession();
          },
        ),
      ),
    );
  }

  Future<void> _showStudyModeHelp() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modo de estudo integrado'),
        content: const Text(
          'Selecione um trecho dentro do PDF para acessar Destacar, Anotar, '
          'Flashcard manual e Explicar com IA. A explicação online oferece os '
          'níveis Rápida, Detalhada e Aprofundada e exige uma conta LexPDF.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  void _runMenuAction(String action) {
    switch (action) {
      case 'open':
        unawaited(_openAnotherPdf());
      case 'close':
        unawaited(_closeActiveTab());
      case 'undo':
        unawaited(_undo());
      case 'redo':
        unawaited(_redo());
      case 'search':
        unawaited(_showDocumentSearch());
      case 'panel':
        _toggleWorkspacePanel();
      case 'status':
        _toggleStatusBar();
      case 'dense':
        _toggleDenseToolbar();
      case 'fullscreen':
        _toggleFullScreen();
      case 'index':
        _startActiveIndexing();
      case 'cancel-index':
        _cancelActiveIndexing();
      case 'palette':
        unawaited(_showCommandPalette());
      case 'chat-pdf':
        unawaited(_openDocumentChat());
      case 'vision-page':
        unawaited(_analyzeActivePageWithAi());
      case 'flashcards':
        unawaited(_openFlashcardCenter());
      case 'study-help':
        unawaited(_showStudyModeHelp());
      case 'shortcuts':
        unawaited(_showShortcutsHelp());
    }
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings() {
    final bindings = <ShortcutActivator, VoidCallback>{};
    void bind(LogicalKeyboardKey key, VoidCallback action,
        {bool shift = false}) {
      bindings[SingleActivator(key, control: true, shift: shift)] = action;
      bindings[SingleActivator(key, meta: true, shift: shift)] = action;
    }

    bind(LogicalKeyboardKey.keyZ, () => unawaited(_undo()));
    bind(LogicalKeyboardKey.keyY, () => unawaited(_redo()));
    bind(LogicalKeyboardKey.keyZ, () => unawaited(_redo()), shift: true);
    bind(LogicalKeyboardKey.keyO, () => unawaited(_openAnotherPdf()));
    bind(LogicalKeyboardKey.keyT, () => unawaited(_openAnotherPdf()));
    bind(LogicalKeyboardKey.keyW, () => unawaited(_closeActiveTab()));
    bind(LogicalKeyboardKey.keyF, () => unawaited(_showDocumentSearch()));
    bind(LogicalKeyboardKey.keyB, _toggleWorkspacePanel);
    bind(LogicalKeyboardKey.keyH, _toggleFullScreen);
    bind(LogicalKeyboardKey.keyI, _startActiveIndexing, shift: true);
    bind(LogicalKeyboardKey.keyP, () => unawaited(_showCommandPalette()), shift: true);
    bindings[const SingleActivator(LogicalKeyboardKey.f11)] = _toggleFullScreen;
    bindings[const SingleActivator(LogicalKeyboardKey.escape)] = () {
      if (_fullScreen) unawaited(_setFullScreen(false));
    };
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tabs.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return CallbackShortcuts(
      bindings: _shortcutBindings(),
      child: Focus(
        focusNode: _shortcutFocus,
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final sidePanelCapable = width >= _sidePanelBreakpoint;
            final desktopMenus =
                !_fullScreen && width >= _desktopMenuBreakpoint;
            final showSidePanel =
                !_fullScreen && sidePanelCapable && _panelVisible;
            return Scaffold(
              body: Column(
                children: [
                  if (desktopMenus) _buildDesktopMenuBar(),
                  if (!_fullScreen)
                    _buildTabStrip(
                      sidePanelCapable: sidePanelCapable,
                    ),
                  if (!_fullScreen) const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        if (showSidePanel) ...[
                          SizedBox(
                            width: 268,
                            child: _buildWorkspacePanel(),
                          ),
                          const VerticalDivider(width: 1),
                        ],
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _buildPdfEditorSurface(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_fullScreen && _statusBarVisible)
                    _buildStatusBar(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopMenuBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _WorkspaceMenuButton(
            label: 'Arquivo',
            onSelected: _runMenuAction,
            items: const [
              _WorkspaceMenuItem('open', 'Abrir PDF', 'Ctrl+O'),
              _WorkspaceMenuItem('close', 'Fechar aba', 'Ctrl+W'),
            ],
          ),
          _WorkspaceMenuButton(
            label: 'Editar',
            onSelected: _runMenuAction,
            items: const [
              _WorkspaceMenuItem('undo', 'Desfazer', 'Ctrl+Z'),
              _WorkspaceMenuItem('redo', 'Refazer', 'Ctrl+Y'),
              _WorkspaceMenuItem('search', 'Pesquisar', 'Ctrl+F'),
            ],
          ),
          _WorkspaceMenuButton(
            label: 'Exibir',
            onSelected: _runMenuAction,
            items: [
              _WorkspaceMenuItem(
                'panel',
                _panelVisible ? 'Ocultar painel lateral' : 'Mostrar painel lateral',
                'Ctrl+B',
              ),
              _WorkspaceMenuItem(
                'status',
                _statusBarVisible ? 'Ocultar barra de status' : 'Mostrar barra de status',
                '',
              ),
              _WorkspaceMenuItem(
                'dense',
                _denseToolbar ? 'Barra confortável' : 'Barra compacta',
                '',
              ),
              _WorkspaceMenuItem(
                'fullscreen',
                _fullScreen
                    ? 'Sair do modo leitura'
                    : 'Modo leitura em tela cheia',
                'Ctrl+H',
              ),
            ],
          ),
          _WorkspaceMenuButton(
            label: 'Ferramentas',
            onSelected: _runMenuAction,
            items: [
              const _WorkspaceMenuItem(
                'index',
                'Iniciar/retomar OCR',
                'Ctrl+Shift+I',
              ),
              const _WorkspaceMenuItem(
                'palette',
                'Paleta de comandos',
                'Ctrl+Shift+P',
              ),
            ],
          ),
          _WorkspaceMenuButton(
            label: 'Estudo',
            onSelected: _runMenuAction,
            items: const [
              _WorkspaceMenuItem(
                'chat-pdf',
                'Chat com este PDF',
                '',
              ),
              _WorkspaceMenuItem(
                'vision-page',
                'Analisar página visualmente com IA',
                '',
              ),
              _WorkspaceMenuItem(
                'flashcards',
                'Central de Flashcards',
                '',
              ),
              _WorkspaceMenuItem(
                'study-help',
                'Como usar o modo de estudo',
                '',
              ),
            ],
          ),
          _WorkspaceMenuButton(
            label: 'Ajuda',
            onSelected: _runMenuAction,
            items: const [
              _WorkspaceMenuItem('shortcuts', 'Atalhos do workspace', ''),
            ],
          ),
          const Spacer(),
          const Icon(Icons.lock_outline, size: 14),
          const SizedBox(width: 5),
          Text(
            'Offline-first',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildWorkspacePanel() {
    final tab = _tabs[_activeIndex];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.space_dashboard_outlined, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Workspace',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Ocultar painel (Ctrl+B)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _toggleWorkspacePanel,
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tab.document.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Página de retomada: ${tab.initialPage}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _PanelAction(
            icon: Icons.search,
            label: 'Pesquisar no documento',
            shortcut: 'Ctrl+F',
            onTap: () => unawaited(_showDocumentSearch()),
          ),
          _PanelAction(
            icon: Icons.document_scanner_outlined,
            label: 'OCR/indexação manual',
            shortcut: 'Ctrl+Shift+I',
            onTap: _startActiveIndexing,
          ),
          _PanelAction(
            icon: Icons.forum_outlined,
            label: 'Chat com este PDF',
            shortcut: '',
            onTap: () => unawaited(_openDocumentChat()),
          ),
          _PanelAction(
            icon: Icons.image_search_outlined,
            label: _visionAnalyzing
                ? 'Analisando página visualmente…'
                : 'Analisar página visualmente com IA',
            shortcut: '',
            onTap: _visionAnalyzing
                ? () {}
                : () => unawaited(_analyzeActivePageWithAi()),
          ),
          _PanelAction(
            icon: Icons.style_outlined,
            label: 'Central de Flashcards',
            shortcut: '',
            onTap: () => unawaited(_openFlashcardCenter()),
          ),
          _PanelAction(
            icon: Icons.school_outlined,
            label: 'Ajuda do modo de estudo',
            shortcut: '',
            onTap: () => unawaited(_showStudyModeHelp()),
          ),
          _PanelAction(
            icon: Icons.terminal_outlined,
            label: 'Paleta de comandos',
            shortcut: 'Ctrl+Shift+P',
            onTap: () => unawaited(_showCommandPalette()),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'PDFs abertos',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final item = _tabs[index];
                final selected = index == _activeIndex;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                  title: Text(
                    item.document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Página ${item.initialPage}'),
                  onTap: () => unawaited(_activateTab(index)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWorkspacePanelSheet() {
    final tab = _tabs[_activeIndex];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Workspace',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                tab.document.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: Text(
                  _fullScreen ? 'Sair da tela cheia' : 'Tela cheia',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleFullScreen();
                },
              ),
              ListTile(
                leading: const Icon(Icons.style_outlined),
                title: const Text('Central de Flashcards'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openFlashcardCenter());
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Pesquisar no documento'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_showDocumentSearch());
                },
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('OCR/indexação manual'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startActiveIndexing();
                },
              ),
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Chat com este PDF'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openDocumentChat());
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_search_outlined),
                title: Text(
                  _visionAnalyzing
                      ? 'Analisando página visualmente…'
                      : 'Analisar página visualmente com IA',
                ),
                enabled: !_visionAnalyzing,
                onTap: _visionAnalyzing
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_analyzeActivePageWithAi());
                      },
              ),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Modo de estudo integrado'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_showStudyModeHelp());
                },
              ),
              ListTile(
                leading: const Icon(Icons.terminal_outlined),
                title: const Text('Paleta de comandos'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_showCommandPalette());
                },
              ),
              const Divider(),
              Text(
                'PDFs abertos',
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < _tabs.length; index++)
                ListTile(
                  selected: index == _activeIndex,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(
                    _tabs[index].document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_activateTab(index));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final tab = _tabs[_activeIndex];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tab.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_tabs.length} aba${_tabs.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Spacer(),
          Text(
            'Ctrl+Shift+P comandos',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip({
    required bool sidePanelCapable,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final height = _denseToolbar ? 40.0 : 48.0;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            IconButton(
              tooltip: sidePanelCapable
                  ? 'Mostrar/ocultar workspace (Ctrl+B)'
                  : 'Abrir workspace',
              visualDensity: _denseToolbar
                  ? VisualDensity.compact
                  : VisualDensity.standard,
              onPressed: sidePanelCapable
                  ? _toggleWorkspacePanel
                  : () => unawaited(_showWorkspacePanelSheet()),
              icon: const Icon(Icons.space_dashboard_outlined, size: 20),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: _denseToolbar ? 3 : 5,
                ),
                itemCount: _tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  final selected = index == _activeIndex;
                  return Material(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => unawaited(_activateTab(index)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 120,
                          maxWidth: 240,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.picture_as_pdf_outlined, size: 17),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tab.document.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fechar aba',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                onPressed: () => unawaited(_closeTab(index)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Paleta de comandos (Ctrl+Shift+P)',
              visualDensity:
                  _denseToolbar ? VisualDensity.compact : VisualDensity.standard,
              onPressed: _showCommandPalette,
              icon: const Icon(Icons.terminal_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Pesquisar no PDF (Ctrl+F)',
              visualDensity:
                  _denseToolbar ? VisualDensity.compact : VisualDensity.standard,
              onPressed: _showDocumentSearch,
              icon: const Icon(Icons.search, size: 20),
            ),
            IconButton(
              tooltip: 'Desfazer (Ctrl+Z)',
              visualDensity:
                  _denseToolbar ? VisualDensity.compact : VisualDensity.standard,
              onPressed: _undo,
              icon: const Icon(Icons.undo, size: 20),
            ),
            IconButton(
              tooltip: 'Refazer (Ctrl+Y)',
              visualDensity:
                  _denseToolbar ? VisualDensity.compact : VisualDensity.standard,
              onPressed: _redo,
              icon: const Icon(Icons.redo, size: 20),
            ),
            IconButton(
              tooltip: 'Nova aba de PDF (Ctrl+T)',
              visualDensity:
                  _denseToolbar ? VisualDensity.compact : VisualDensity.standard,
              onPressed: _picking ? null : _openAnotherPdf,
              icon: _picking
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 22),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab {
  _WorkspaceTab({
    required this.document,
    required this.initialPage,
  });

  final DocumentRef document;
  int initialPage;
  int generation = 0;
  int? pageCount;
  PdfDocument? viewerDocument;
  bool localizedIndexPending = false;
}

class _WorkspaceOcrTask {
  bool running = false;
  bool automatic = false;
  bool cancelRequested = false;
  PdfOcrProgress? progress;
  PdfOcrSummary? summary;
  Object? error;
}

class _WorkspaceCommand {
  const _WorkspaceCommand({
    required this.label,
    required this.shortcut,
    required this.icon,
    required this.action,
  });

  final String label;
  final String shortcut;
  final IconData icon;
  final VoidCallback action;
}

class _WorkspaceMenuItem {
  const _WorkspaceMenuItem(this.value, this.label, this.shortcut);

  final String value;
  final String label;
  final String shortcut;
}

class _WorkspaceMenuButton extends StatelessWidget {
  const _WorkspaceMenuButton({
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final List<_WorkspaceMenuItem> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<String>(
            value: item.value,
            child: SizedBox(
              width: 260,
              child: Row(
                children: [
                  Expanded(child: Text(item.label)),
                  if (item.shortcut.isNotEmpty)
                    Text(
                      item.shortcut,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Text(label),
      ),
    );
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: shortcut.isEmpty ? null : _ShortcutBadge(shortcut),
      onTap: onTap,
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

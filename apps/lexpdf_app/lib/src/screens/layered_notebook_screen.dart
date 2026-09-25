import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_clipboard.dart';
import 'package:fluent_editor/handlers/handle_select_all.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ai/remote_vision_service.dart';
import '../core/backend/backend_config.dart';
import '../core/ink/ink_models.dart';
import '../core/notebook/ink_shape_recognizer.dart';
import '../core/notebook/legacy_notebook_text_migrator.dart';
import '../core/notebook/notebook_document_file_service.dart';
import '../core/documents/native_android_file_picker_service.dart';
import '../core/notebook/notebook_history.dart';
import '../core/notebook/notebook_object_models.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_knowledge_rag_store.dart';
import '../core/storage/local_notebook_document_store.dart';
import '../core/storage/local_notebook_layer_store.dart';
import '../core/storage/local_notebook_object_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_editor_chrome.dart';
import '../widgets/notebook_editor_toolbar.dart';
import '../widgets/notebook_layer_ink_view.dart';
import '../widgets/notebook_object_layer.dart';
import '../widgets/notebook_page_background.dart';
import '../widgets/notebook_rich_document_surface.dart';
import '../widgets/notebook_ruler_overlay.dart';
import '../widgets/notebook_wordpad_chrome.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({required this.inkStore, super.key});

  final LocalInkStore inkStore;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  static const double _moveStep = 12;
  static const double _scaleDown = 0.9;
  static const double _scaleUp = 1.1;
  static const double _rotationStep = math.pi / 12;
  static const double _widthDown = 0.85;
  static const double _widthUp = 1.15;
  static const String _defaultNotebookFontFamily = 'Arial';
  static const double _defaultNotebookFontSize = 12;
  static const InkShapeRecognizer _shapeRecognizer = InkShapeRecognizer();

  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  final GlobalKey _pageViewportKey = GlobalKey();
  final NotebookHistoryController _history = NotebookHistoryController();
  final ScrollController _toolbarScrollController = ScrollController();
  final TransformationController _pageTransformController =
      TransformationController();
  late final LocalNotebookObjectStore _objectStore;
  late final LocalNotebookLayerStore _layerStore;
  late final LocalNotebookDocumentStore _documentStore;
  late final Future<void> _loadFuture;
  static const LegacyNotebookTextMigrator _legacyTextMigrator =
      LegacyNotebookTextMigrator();
  static const NotebookDocumentFileService _documentFileService =
      NotebookDocumentFileService();
  static const Duration _documentAutosaveDelay = Duration(milliseconds: 650);
  static const int _maximumOfficeFileBytes = 32 * 1024 * 1024;

  FluentDocument? _richDocument;
  String? _richDocumentPageId;
  Timer? _richDocumentSaveTimer;
  int _lastDocumentContentVersion = -1;
  bool _richDocumentMigratedLegacyText = false;

  List<InkNotebook> _notebooks = const [];
  List<InkNotebookPage> _pages = const [];
  InkNotebook? _currentNotebook;
  InkNotebookPage? _currentPage;
  List<InkStroke> _allStrokes = const [];
  List<NotebookObject> _allObjects = const [];
  List<NotebookLayer> _layers = const [];
  Map<String, String> _strokeLayerIds = const {};
  Map<String, String> _objectLayerIds = const {};
  String? _activeLayerId;

  InkTool _tool = InkTool.pen;
  int _colorValue = 0xFF1C1B1F;
  double _width = 3.0;
  bool _stylusOnly = true;
  bool _eraserMode = false;
  bool _lassoMode = false;
  bool _clipboardAvailable = false;
  int _selectionCount = 0;
  bool _textMode = true;
  bool _pointerMode = false;
  bool _handMode = false;
  bool _rulerMode = false;
  bool _showDocumentRuler = true;
  double _zoom = 1.0;
  String? _selectedObjectId;
  String _defaultTextFontFamily = _defaultNotebookFontFamily;
  double _defaultTextFontSize = _defaultNotebookFontSize;
  bool _defaultTextBold = false;
  bool _defaultTextItalic = false;
  bool _defaultTextUnderline = false;
  NotebookTextAlign _defaultTextAlign = NotebookTextAlign.left;
  int _defaultTextColorValue = 0xFF000000;
  bool _suppressMutationHistory = false;
  bool _legacyDocAvailable = false;
  bool _notebookVisionIndexing = false;

  static const _palette = <int>[
    0xFF1C1B1F,
    0xFF246BFD,
    0xFFD32F2F,
    0xFF2E7D32,
    0xFF7B1FA2,
    0xFFFFA000,
    0xFFFFD54F,
    0xFF00ACC1,
  ];

  @override
  void initState() {
    super.initState();
    _objectStore = LocalNotebookObjectStore(widget.inkStore.db);
    _layerStore = LocalNotebookLayerStore(widget.inkStore.db);
    _documentStore = LocalNotebookDocumentStore(widget.inkStore.db);
    _loadFuture = _loadInitial();
    unawaited(_loadDocumentFormatCapabilities());
  }

  Future<void> _loadDocumentFormatCapabilities() async {
    final available = await _documentFileService.supportsLegacyDoc();
    if (mounted) setState(() => _legacyDocAvailable = available);
  }

  @override
  void dispose() {
    _richDocumentSaveTimer?.cancel();
    final document = _richDocument;
    if (document != null) {
      document.removeListener(_onRichDocumentChanged);
      unawaited(_persistRichDocumentNow());
      document.dispose();
    }
    _toolbarScrollController.dispose();
    _pageTransformController.dispose();
    super.dispose();
  }

  NotebookLayer? get _activeLayer {
    final id = _activeLayerId;
    if (id == null) return null;
    for (final layer in _layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  bool get _canEditActiveLayer {
    final layer = _activeLayer;
    return layer != null && layer.isVisible && !layer.isLocked;
  }

  Set<String> get _visibleLayerIds => _layers
      .where((layer) => layer.isVisible)
      .map((layer) => layer.id)
      .toSet();

  List<InkStroke> get _activeStrokes => _allStrokes
      .where((stroke) => _strokeLayerIds[stroke.id] == _activeLayerId)
      .toList(growable: false);

  List<InkStroke> get _backgroundStrokes => _allStrokes
      .where((stroke) {
        final layerId = _strokeLayerIds[stroke.id];
        return layerId != _activeLayerId && _visibleLayerIds.contains(layerId);
      })
      .toList(growable: false);

  List<NotebookObject> get _activeObjects => _allObjects
      .where(
        (object) =>
            object.type != NotebookObjectType.text &&
            _objectLayerIds[object.id] == _activeLayerId,
      )
      .toList(growable: false);

  List<NotebookObject> get _backgroundObjects => _allObjects
      .where((object) {
        if (object.type == NotebookObjectType.text) return false;
        final layerId = _objectLayerIds[object.id];
        return layerId != _activeLayerId && _visibleLayerIds.contains(layerId);
      })
      .toList(growable: false);

  Future<void> _loadInitial() async {
    final page = await widget.inkStore.ensureDefaultPage();
    final notebooks = await widget.inkStore.listNotebooks();
    final notebook = notebooks.firstWhere(
      (item) => item.id == page.notebookId,
      orElse: () => notebooks.first,
    );
    final pages = await widget.inkStore.listPages(notebook.id);
    final target = pages.firstWhere(
      (item) => item.id == page.id,
      orElse: () => pages.first,
    );
    _notebooks = notebooks;
    _currentNotebook = notebook;
    _pages = pages;
    _currentPage = target;
    await _loadPageContent(target.id);
    _history.clear();
  }

  Future<void> _loadPageContent(
    String pageId, {
    String? preferredLayerId,
  }) async {
    await _layerStore.ensureDefaultLayer(pageId);
    final layers = await _layerStore.listLayers(pageId);
    final strokes = await widget.inkStore.listStrokes(pageId);
    final objects = await _objectStore.listObjects(pageId);
    await _loadRichDocument(pageId, objects);
    final strokeMap = await _layerStore.itemLayerMap(
      pageId,
      NotebookLayerItemType.stroke,
    );
    final objectMap = await _layerStore.itemLayerMap(
      pageId,
      NotebookLayerItemType.object,
    );
    final fallback = layers.first;
    for (final stroke in strokes) {
      if (!strokeMap.containsKey(stroke.id)) {
        await _layerStore.assignStroke(fallback.id, stroke.id);
        strokeMap[stroke.id] = fallback.id;
      }
    }
    for (final object in objects) {
      if (!objectMap.containsKey(object.id)) {
        await _layerStore.assignObject(fallback.id, object.id);
        objectMap[object.id] = fallback.id;
      }
    }
    final selected = layers.any((layer) => layer.id == preferredLayerId)
        ? preferredLayerId
        : layers.first.id;
    _layers = layers;
    _allStrokes = strokes;
    _allObjects = objects;
    _strokeLayerIds = Map.unmodifiable(strokeMap);
    _objectLayerIds = Map.unmodifiable(objectMap);
    _activeLayerId = selected;
  }

  Future<void> _loadRichDocument(
    String pageId,
    List<NotebookObject> legacyObjects,
  ) async {
    if (_richDocumentPageId == pageId && _richDocument != null) return;

    await _persistRichDocumentNow();
    _richDocumentSaveTimer?.cancel();
    final previous = _richDocument;
    previous?.removeListener(_onRichDocumentChanged);

    final stored = await _documentStore.read(pageId);
    late final FluentDocument document;
    late final bool migratedLegacyText;
    if (stored != null) {
      document = FluentDocument.fromJson(
        jsonDecode(stored.documentJson) as Map<String, dynamic>,
      );
      migratedLegacyText = stored.migratedLegacyText;
    } else {
      document = FluentDocument(
        content: _legacyTextMigrator.migrate(legacyObjects),
      );
      document.pendingFontFamily = _defaultNotebookFontFamily;
      document.pendingFontSize = _defaultNotebookFontSize;
      document.pendingTextAlign = NotebookTextAlign.left.dbValue;
      migratedLegacyText = true;
      await _documentStore.upsert(
        pageId: pageId,
        documentJson: document.toJson(),
        migratedLegacyText: migratedLegacyText,
      );
    }

    _richDocument = document;
    _richDocumentPageId = pageId;
    _richDocumentMigratedLegacyText = migratedLegacyText;
    _lastDocumentContentVersion = document.contentVersion;
    _syncRibbonStateFromDocument(document);
    document.addListener(_onRichDocumentChanged);

    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _onRichDocumentChanged() {
    final document = _richDocument;
    if (document == null) return;

    final ribbonChanged = _syncRibbonStateFromDocument(document);
    if (document.contentVersion != _lastDocumentContentVersion) {
      _lastDocumentContentVersion = document.contentVersion;
      _richDocumentSaveTimer?.cancel();
      _richDocumentSaveTimer = Timer(
        _documentAutosaveDelay,
        () => unawaited(_persistRichDocumentNow()),
      );
    }
    if (ribbonChanged && mounted) setState(() {});
  }

  bool _syncRibbonStateFromDocument(FluentDocument document) {
    final bold = document.pendingStyles.contains('bold');
    final italic = document.pendingStyles.contains('italic');
    final underline = document.pendingStyles.contains('underline');
    final align = NotebookTextAlign.fromDb(document.pendingTextAlign);
    final color = _documentColorValue(document.pendingColor);
    final changed =
        _defaultTextFontFamily != document.pendingFontFamily ||
        _defaultTextFontSize != document.pendingFontSize ||
        _defaultTextBold != bold ||
        _defaultTextItalic != italic ||
        _defaultTextUnderline != underline ||
        _defaultTextAlign != align ||
        _defaultTextColorValue != color;
    _defaultTextFontFamily = document.pendingFontFamily;
    _defaultTextFontSize = document.pendingFontSize;
    _defaultTextBold = bold;
    _defaultTextItalic = italic;
    _defaultTextUnderline = underline;
    _defaultTextAlign = align;
    _defaultTextColorValue = color;
    return changed;
  }

  int _documentColorValue(String? cssColor) {
    final value = cssColor?.trim();
    if (value == null || value.isEmpty || !value.startsWith('#')) {
      return 0xFF000000;
    }
    final hex = value.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return 0xFF000000;
    if (hex.length == 6) return 0xFF000000 | parsed;
    if (hex.length == 8) return parsed;
    return 0xFF000000;
  }

  String _cssColor(int value) =>
      '#${(value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _persistRichDocumentNow() async {
    final document = _richDocument;
    final pageId = _richDocumentPageId;
    if (document == null || pageId == null) return;
    await _documentStore.upsert(
      pageId: pageId,
      documentJson: document.toJson(),
      migratedLegacyText: _richDocumentMigratedLegacyText,
    );
  }

  List<InkStroke> _snapshotStrokes() {
    final activeIds = _strokeLayerIds.entries
        .where((entry) => entry.value == _activeLayerId)
        .map((entry) => entry.key)
        .toSet();
    final currentActive = _canvasKey.currentState?.strokes ?? _activeStrokes;
    return [
      ..._allStrokes.where((stroke) => !activeIds.contains(stroke.id)),
      ...currentActive,
    ];
  }

  NotebookPageSnapshot _captureSnapshot() => NotebookPageSnapshot.capture(
    strokes: _snapshotStrokes(),
    objects: _allObjects,
    strokeLayerIds: _strokeLayerIds,
    objectLayerIds: _objectLayerIds,
  );

  void _recordHistory() {
    if (_suppressMutationHistory || _currentPage == null) return;
    _history.record(_captureSnapshot());
  }

  void _runCanvasMutation(VoidCallback action) {
    if (!_canEditActiveLayer) return;
    _recordHistory();
    _suppressMutationHistory = true;
    try {
      action();
    } finally {
      _suppressMutationHistory = false;
    }
    _syncActiveCanvasToState();
  }

  void _syncActiveCanvasToState() {
    final activeIds = _strokeLayerIds.entries
        .where((entry) => entry.value == _activeLayerId)
        .map((entry) => entry.key)
        .toSet();
    final current = _canvasKey.currentState?.strokes ?? _activeStrokes;
    if (!mounted) return;
    setState(() {
      _allStrokes = [
        ..._allStrokes.where((stroke) => !activeIds.contains(stroke.id)),
        ...current,
      ];
    });
  }

  Future<void> _restoreSnapshot(NotebookPageSnapshot snapshot) async {
    final page = _currentPage;
    if (page == null) return;
    _suppressMutationHistory = true;
    try {
      await widget.inkStore.replacePageStrokes(page.id, snapshot.strokes);
      await _objectStore.replacePageObjects(page.id, snapshot.objects);
      await _layerStore.replaceAssignments(
        pageId: page.id,
        strokeLayerIds: snapshot.strokeLayerIds,
        objectLayerIds: snapshot.objectLayerIds,
      );
      await _loadPageContent(page.id, preferredLayerId: _activeLayerId);
    } finally {
      _suppressMutationHistory = false;
    }
    if (!mounted) return;
    setState(() {
      _selectionCount = 0;
      _selectedObjectId = null;
      _clipboardAvailable = false;
    });
    _canvasKey.currentState?.clearSelection();
  }

  Future<void> _undoHistory() async {
    final target = _history.undo(_captureSnapshot());
    if (target != null) await _restoreSnapshot(target);
  }

  Future<void> _redoHistory() async {
    final target = _history.redo(_captureSnapshot());
    if (target != null) await _restoreSnapshot(target);
  }

  Future<void> _reloadCurrent({
    String? pageId,
    String? preferredLayerId,
  }) async {
    final notebook = _currentNotebook;
    if (notebook == null) return;
    final notebooks = await widget.inkStore.listNotebooks();
    final currentNotebook = notebooks.firstWhere(
      (item) => item.id == notebook.id,
      orElse: () => notebooks.first,
    );
    var pages = await widget.inkStore.listPages(currentNotebook.id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(currentNotebook.id);
      pages = await widget.inkStore.listPages(currentNotebook.id);
    }
    final target = pageId == null
        ? pages.firstWhere(
            (item) => item.id == _currentPage?.id,
            orElse: () => pages.first,
          )
        : pages.firstWhere(
            (item) => item.id == pageId,
            orElse: () => pages.first,
          );
    await _loadPageContent(target.id, preferredLayerId: preferredLayerId);
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _currentNotebook = currentNotebook;
      _pages = pages;
      _currentPage = target;
      _selectionCount = 0;
      _lassoMode = false;
      _eraserMode = false;
      _clipboardAvailable = false;
      _selectedObjectId = null;
      _textMode = true;
      _pointerMode = false;
      _handMode = false;
    });
    _history.clear();
  }

  int get _wordCount {
    final combined = _richDocument?.content.text.trim() ?? '';
    if (combined.isEmpty) return 0;
    return RegExp(r'\S+').allMatches(combined).length;
  }

  Widget _buildViewRibbon() {
    return NotebookWordPadViewRibbon(
      showDocumentRuler: _showDocumentRuler,
      onShowDocumentRulerChanged: (value) =>
          setState(() => _showDocumentRuler = value),
      onLayers: () => unawaited(_showLayers()),
      onZoomOut: () => _zoomBy(0.85),
      onZoomIn: () => _zoomBy(1.15),
      onActualSize: () => _setZoom(1),
      onFitPage: _resetZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Não foi possível abrir o caderno: ${snapshot.error}',
              ),
            );
          }
          final page = _currentPage;
          if (page == null) {
            return const Center(child: Text('Nenhuma página disponível.'));
          }
          final pageIndex = _pageIndex;
          return NotebookWordPadScaffold(
            title: _currentNotebook?.title ?? 'Cadernos',
            homeRibbon: _buildTextFormattingToolbar(),
            insertRibbon: _buildInsertRibbon(),
            drawingRibbon: _buildToolbar(),
            viewRibbon: _buildViewRibbon(),
            document: _buildPageViewport(page),
            pageIndex: pageIndex < 0 ? 0 : pageIndex,
            pageCount: _pages.length,
            wordCount: _wordCount,
            layerName: _activeLayer?.name ?? 'Camada 1',
            zoom: _zoom,
            showDocumentRuler: _showDocumentRuler,
            onOpenDocument: () => unawaited(_openRichDocumentFile()),
            onSaveDocx: () => unawaited(_saveRichDocumentAs('docx')),
            onSaveTxt: () => unawaited(_saveRichDocumentAs('txt')),
            onExportPdf: () => unawaited(_saveRichDocumentAs('pdf')),
            onSaveDoc: () => unawaited(_saveRichDocumentAs('doc')),
            onSaveRtf: () => unawaited(_saveRichDocumentAs('rtf')),
            legacyDocAvailable: _legacyDocAvailable,
            onIndexImagesAi: () => unawaited(_indexNotebookImagesWithAi()),
            onRibbonTabChanged: (tab) {
              if (tab == NotebookRibbonTab.home ||
                  tab == NotebookRibbonTab.insert) {
                _activateTextMode();
              }
              if (tab == NotebookRibbonTab.drawing) {
                setState(() => _textMode = false);
              }
            },
            onNewNotebook: () => unawaited(_createNotebook()),
            onRenameNotebook: () => unawaited(_renameNotebook()),
            onDeleteNotebook: _notebooks.length > 1
                ? () => unawaited(_deleteNotebook())
                : null,
            onNewPage: () => unawaited(_addPage()),
            onDuplicatePage: () => unawaited(_duplicatePage()),
            onDeletePage: _pages.length > 1
                ? () => unawaited(_deletePage())
                : null,
            onLayers: () => unawaited(_showLayers()),
            onPreviousPage: pageIndex > 0
                ? () => unawaited(_openPageAt(pageIndex - 1))
                : null,
            onNextPage: pageIndex >= 0 && pageIndex < _pages.length - 1
                ? () => unawaited(_openPageAt(pageIndex + 1))
                : null,
            onUndo: _textMode
                ? () => _richDocument?.undo()
                : (_history.canUndo ? () => unawaited(_undoHistory()) : null),
            onRedo: _textMode
                ? () => _richDocument?.redo()
                : (_history.canRedo ? () => unawaited(_redoHistory()) : null),
            onZoomChanged: _setZoom,
            onFitPage: _resetZoom,
          );
        },
      ),
    );
  }

  Widget _buildPageViewport(InkNotebookPage page) {
    final document = _richDocument;
    return ColoredBox(
      key: _pageViewportKey,
      color: const Color(0xFFD9DDE2),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _pageTransformController,
              minScale: 0.25,
              maxScale: 4,
              panEnabled: _handMode,
              scaleEnabled: _handMode,
              boundaryMargin: const EdgeInsets.all(220),
              onInteractionEnd: (_) {
                final scale = _pageTransformController.value
                    .getMaxScaleOnAxis();
                if (mounted) {
                  setState(() => _zoom = scale.clamp(0.25, 4.0));
                }
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: page.width / page.height,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                      border: Border.all(color: const Color(0xFFC6C9CE)),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 5,
                          offset: Offset(0, 2),
                          color: Color(0x26000000),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotebookPageBackground(background: page.background),
                        NotebookObjectLayer(
                          objects: _backgroundObjects,
                          enabled: false,
                          selectedId: null,
                          onObjectChanged: (_) {},
                          onObjectDoubleTap: (_) {},
                          onSelectionChanged: (_) {},
                        ),
                        if (document != null)
                          NotebookRichDocumentSurface(
                            key: ValueKey('rich-document-${page.id}'),
                            document: document,
                            enabled: _textMode && !_handMode,
                          ),
                        NotebookLayerInkView(strokes: _backgroundStrokes),
                        IgnorePointer(
                          ignoring:
                              !_canEditActiveLayer ||
                              _textMode ||
                              _pointerMode ||
                              _handMode,
                          child: InkCanvas(
                            key: _canvasKey,
                            initialStrokes: _activeLayer?.isVisible == true
                                ? _activeStrokes
                                : const [],
                            pageId: page.id,
                            tool: _tool,
                            colorValue: _colorValue,
                            strokeWidth: _effectiveWidth,
                            stylusOnly: _stylusOnly,
                            eraserMode: _eraserMode,
                            lassoMode: _lassoMode,
                            onWillMutate: _recordHistory,
                            onStrokeCompleted: _onStrokeCompleted,
                            onStrokeUpdated: _onStrokeUpdated,
                            onStrokeErased: _onStrokeErased,
                            onSelectionChanged: (ids) {
                              if (mounted) {
                                setState(() => _selectionCount = ids.length);
                              }
                            },
                          ),
                        ),
                        NotebookObjectLayer(
                          objects: _activeLayer?.isVisible == true
                              ? _activeObjects
                              : const [],
                          enabled:
                              !_textMode &&
                              _pointerMode &&
                              !_handMode &&
                              _canEditActiveLayer,
                          selectedId: _selectedObjectId,
                          onObjectChanged: _onObjectChanged,
                          onSelectionChanged: (id) {
                            if (!mounted) return;
                            setState(() => _selectedObjectId = id);
                          },
                        ),
                        NotebookRulerOverlay(enabled: _rulerMode),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_textMode && _pointerMode)
            Positioned(
              left: 16,
              bottom: 16,
              child: Material(
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: 0.94),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    _selectedObjectId == null
                        ? 'Selecionar: clique em uma imagem ou forma'
                        : 'Objeto selecionado: arraste para mover ou use os controles acima',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _indexNotebookImagesWithAi() async {
    if (_notebookVisionIndexing) return;
    final notebook = _currentNotebook;
    if (notebook == null) return;

    final rows = widget.inkStore.db.database.select('''
      SELECT o.id, o.image_path, p.page_number
      FROM notebook_objects o
      JOIN notebook_pages p ON p.id = o.page_id
      WHERE p.notebook_id = ?
        AND o.type = 'image'
        AND trim(COALESCE(o.image_path, '')) <> ''
      ORDER BY p.page_number, o.created_at;
    ''', [notebook.id]);
    if (rows.isEmpty) {
      _showNotebookMessage(
        'Este caderno não possui imagens locais para analisar.',
      );
      return;
    }

    setState(() => _notebookVisionIndexing = true);
    var indexed = 0;
    var skipped = 0;
    try {
      const config = BackendConfig.fromEnvironment;
      if (!config.hasAiGateway || !config.hasSupabase) {
        throw StateError(
          'A análise visual exige gateway e autenticação LexPDF.',
        );
      }
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null || token.trim().isEmpty) {
        throw StateError('Entre na sua conta LexPDF para analisar imagens.');
      }
      final base = Uri.parse(config.aiGatewayUrl);
      final vision = RemoteAiVisionService(
        endpoint: base.replace(
          path: '/v1/ai/vision',
          query: null,
          fragment: null,
        ),
        bearerToken: token,
      );
      final knowledge = LocalKnowledgeRagStore(widget.inkStore.db);

      for (final row in rows) {
        final path = row['image_path'] as String?;
        if (path == null || path.isEmpty) {
          skipped++;
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          skipped++;
          continue;
        }
        try {
          final original = await file.readAsBytes();
          final decoded = img.decodeImage(original);
          if (decoded == null) {
            skipped++;
            continue;
          }
          var prepared = decoded;
          final maxDimension = math.max(decoded.width, decoded.height);
          if (maxDimension > 1800) {
            final scale = 1800 / maxDimension;
            prepared = img.copyResize(
              decoded,
              width: math.max(1, (decoded.width * scale).round()).toInt(),
              height: math.max(1, (decoded.height * scale).round()).toInt(),
            );
          }
          final bytes = img.encodeJpg(prepared, quality: 86);
          if (bytes.length > RemoteAiVisionService.maxImageBytes) {
            skipped++;
            continue;
          }
          final pageNumber = row['page_number'] as int;
          final result = await vision.analyze(
            imageBytes: bytes,
            mimeType: 'image/jpeg',
            prompt:
                'Descreva fielmente esta imagem inserida no caderno '
                '"${notebook.title}", página $pageNumber, para pesquisa semântica. '
                'Preserve tabelas, diagramas, gráficos, texto legível, relações '
                'e anotações manuscritas. Não use conhecimento externo.',
          );
          await knowledge.upsertVisualDescription(
            id: 'notebook-image:${row['id']}',
            sourceKind: 'notebook_visual',
            ownerId: notebook.id,
            ownerTitle: 'Imagem — ${notebook.title}',
            pageNumber: pageNumber,
            imagePath: path,
            description: result.text,
          );
          indexed++;
        } catch (_) {
          skipped++;
        }
      }

      _showNotebookMessage(
        'IA visual: $indexed imagem${indexed == 1 ? '' : 's'} '
        'indexada${indexed == 1 ? '' : 's'}'
        '${skipped == 0 ? '.' : '; $skipped ignorada${skipped == 1 ? '' : 's'}.'}',
      );
    } catch (error) {
      _showNotebookMessage('Não foi possível indexar imagens com IA: $error');
    } finally {
      if (mounted) setState(() => _notebookVisionIndexing = false);
    }
  }

  Future<void> _openRichDocumentFile() async {
    final group = XTypeGroup(
      label: 'Documentos de texto',
      extensions: [
        'docx',
        'txt',
        'rtf',
        if (_legacyDocAvailable) 'doc',
      ],
    );
    late final String selectedPath;
    late final String selectedName;
    if (Platform.isAndroid) {
      final picked = await const NativeAndroidFilePickerService().pickFile(
        extensions: group.extensions ?? const <String>[],
      );
      if (picked == null) return;
      selectedPath = picked.path;
      selectedName = picked.name;
    } else {
      final selected = await openFile(acceptedTypeGroups: [group]);
      if (selected == null) return;
      selectedPath = selected.path;
      selectedName = selected.name;
    }

    try {
      final source = File(selectedPath);
      final length = await source.length();
      if (length > _maximumOfficeFileBytes) {
        throw StateError('Arquivo excede o limite seguro de 32 MB.');
      }
      final extension = selectedName.contains('.')
          ? selectedName.split('.').last.toLowerCase()
          : '';
      final root = await _documentFileService.importBytes(
        await source.readAsBytes(),
        extension,
      );
      final document = _richDocument;
      if (document == null) return;
      document.loadContent(root);
      _richDocumentMigratedLegacyText = true;
      _lastDocumentContentVersion = document.contentVersion;
      await _persistRichDocumentNow();
      _activateTextMode();
      _showNotebookMessage('Documento aberto: $selectedName');
    } catch (error) {
      _showNotebookMessage('Não foi possível abrir o documento: $error');
    }
  }

  Future<void> _saveRichDocumentAs(String extension) async {
    final document = _richDocument;
    if (document == null) return;
    final ext = extension.toLowerCase();
    final notebookName = (_currentNotebook?.title ?? 'documento')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '_')
        .trim();
    final safeName = notebookName.isEmpty ? 'documento' : notebookName;
    final group = XTypeGroup(label: ext.toUpperCase(), extensions: [ext]);
    final location = await getSaveLocation(
      suggestedName: '$safeName.$ext',
      acceptedTypeGroups: [group],
    );
    if (location == null) return;
    try {
      final bytes = await _documentFileService.exportBytes(document, ext);
      await File(location.path).writeAsBytes(bytes, flush: true);
      _showNotebookMessage('Arquivo salvo: ${location.path}');
    } catch (error) {
      _showNotebookMessage('Não foi possível salvar .$ext: $error');
    }
  }

  void _showNotebookMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _zoomBy(double factor) {
    final next = (_zoom * factor).clamp(0.25, 4.0);
    _setZoom(next);
  }

  void _setZoom(double value) {
    final next = value.clamp(0.25, 4.0);
    final renderObject = _pageViewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final viewportCenter = renderObject.size.center(Offset.zero);
      final sceneCenter = _pageTransformController.toScene(viewportCenter);
      final matrix = Matrix4.identity()
        ..multiply(
          Matrix4.translationValues(viewportCenter.dx, viewportCenter.dy, 0),
        )
        ..multiply(Matrix4.diagonal3Values(next, next, 1))
        ..multiply(
          Matrix4.translationValues(-sceneCenter.dx, -sceneCenter.dy, 0),
        );
      _pageTransformController.value = matrix;
    } else {
      _pageTransformController.value = Matrix4.diagonal3Values(next, next, 1);
    }
    if (mounted) setState(() => _zoom = next);
  }

  void _resetZoom() {
    _pageTransformController.value = Matrix4.identity();
    if (mounted) setState(() => _zoom = 1.0);
  }

  // Retained for callers that may reintroduce a custom zoom command.
  // ignore: unused_element
  Future<void> _showCustomZoomDialog() async {
    final controller = TextEditingController(text: '${(_zoom * 100).round()}');
    final percent = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zoom personalizado'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Zoom (%)',
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (percent == null || percent <= 0) return;
    _setZoom(percent / 100);
  }

  // Kept for the legacy compact navigation path.
  // ignore: unused_element
  Widget _buildLayerStatus() {
    final layer = _activeLayer;
    if (layer == null) return const SizedBox.shrink();
    return NotebookLayerStatus(
      layer: layer,
      layerCount: _layers.length,
      onTap: _showLayers,
    );
  }

  // Kept for compatibility with the previous notebook chrome.
  // ignore: unused_element
  Widget _buildNotebookNavigation() {
    final pageIndex = _pageIndex;
    return NotebookNavigationBar(
      notebooks: _notebooks,
      currentNotebook: _currentNotebook,
      currentPage: _currentPage,
      pageIndex: pageIndex,
      pageCount: _pages.length,
      backgroundLabel: _backgroundLabel,
      onNotebookChanged: (id) => unawaited(_switchNotebook(id)),
      onPreviousPage: pageIndex > 0
          ? () => unawaited(_openPageAt(pageIndex - 1))
          : null,
      onNextPage: pageIndex >= 0 && pageIndex < _pages.length - 1
          ? () => unawaited(_openPageAt(pageIndex + 1))
          : null,
      onAddPage: () => unawaited(_addPage()),
      onDuplicatePage: _currentPage == null
          ? null
          : () => unawaited(_duplicatePage()),
      onMovePageLeft: pageIndex > 0 ? () => unawaited(_movePage(-1)) : null,
      onMovePageRight: pageIndex >= 0 && pageIndex < _pages.length - 1
          ? () => unawaited(_movePage(1))
          : null,
      onDeletePage: _pages.length > 1 ? () => unawaited(_deletePage()) : null,
      onBackgroundChanged: (value) => unawaited(_setBackground(value)),
    );
  }

  int get _pageIndex =>
      _pages.indexWhere((item) => item.id == _currentPage?.id);

  double get _effectiveWidth => switch (_tool) {
    InkTool.pen => _width,
    InkTool.pencil => _width * 0.8,
    InkTool.highlighter => _width * 5,
  };

  NotebookObject? get _selectedObject {
    final id = _selectedObjectId;
    if (id == null) return null;
    for (final object in _activeObjects) {
      if (object.id == id) return object;
    }
    return null;
  }

  Widget _buildToolbar() {
    final selectedObject = _selectedObject;
    return NotebookEditorToolbar(
      controller: _toolbarScrollController,
      editable: _canEditActiveLayer,
      pointerMode: _pointerMode,
      handMode: _handMode,
      tool: _tool,
      eraserMode: _eraserMode,
      lassoMode: _lassoMode,
      clipboardAvailable: _clipboardAvailable,
      selectionCount: _selectionCount,
      rulerMode: _rulerMode,
      palette: _palette,
      colorValue: selectedObject?.colorValue ?? _colorValue,
      width: selectedObject?.strokeWidth ?? _width,
      stylusOnly: _stylusOnly,
      selectedObject: selectedObject,
      onPointerModeChanged: (value) => setState(() {
        _pointerMode = value;
        if (value) {
          _textMode = false;
          _handMode = false;
          _eraserMode = false;
          _lassoMode = false;
          _selectionCount = 0;
        } else {
          _selectedObjectId = null;
        }
      }),
      onHandModeChanged: (value) => setState(() {
        _handMode = value;
        if (value) {
          _textMode = false;
          _pointerMode = false;
          _eraserMode = false;
          _lassoMode = false;
          _selectionCount = 0;
          _selectedObjectId = null;
          _canvasKey.currentState?.clearSelection();
        }
      }),
      onToolChanged: (value) => setState(() {
        _tool = value;
        _textMode = false;
        _eraserMode = false;
        _lassoMode = false;
        _pointerMode = false;
        _handMode = false;
        _selectedObjectId = null;
        _selectionCount = 0;
      }),
      onEraserModeChanged: (value) => setState(() {
        _eraserMode = value;
        if (value) {
          _textMode = false;
          _lassoMode = false;
          _pointerMode = false;
          _handMode = false;
          _selectedObjectId = null;
        }
      }),
      onLassoModeChanged: (value) => setState(() {
        _lassoMode = value;
        if (value) _textMode = false;
        _eraserMode = false;
        _pointerMode = false;
        _handMode = false;
        _selectedObjectId = null;
        if (!value) _selectionCount = 0;
      }),
      onMoveSelectionLeft: () => _moveSelection(-_moveStep, 0),
      onMoveSelectionRight: () => _moveSelection(_moveStep, 0),
      onScaleSelectionDown: () => _scaleSelection(_scaleDown),
      onScaleSelectionUp: () => _scaleSelection(_scaleUp),
      onRotateSelectionLeft: () => _rotateSelection(-_rotationStep),
      onRotateSelectionRight: () => _rotateSelection(_rotationStep),
      onDecreaseSelectionWidth: () => _adjustSelectionWidth(_widthDown),
      onIncreaseSelectionWidth: () => _adjustSelectionWidth(_widthUp),
      onCopySelection: _copySelection,
      onDuplicateSelection: _duplicateSelection,
      onCutSelection: _cutSelection,
      onRecognizeSelectedInk: () => unawaited(_recognizeSelectedInk()),
      onPasteClipboard: _pasteClipboard,
      onAddText: () => unawaited(_addText()),
      onAddShape: (type) => unawaited(_addShape(type)),
      onAddImage: () => unawaited(_addImage()),
      onScaleObjectDown: () => _scaleSelectedObject(_scaleDown),
      onScaleObjectUp: () => _scaleSelectedObject(_scaleUp),
      onDuplicateObject: () => unawaited(_duplicateSelectedObject()),
      onRotateObjectLeft: () => _rotateSelectedObject(-_rotationStep),
      onRotateObjectRight: () => _rotateSelectedObject(_rotationStep),
      onEditTextObject: _activateTextMode,
      onDeleteSelectedObject: () => unawaited(_deleteSelectedObject()),
      onRulerModeChanged: (value) => setState(() => _rulerMode = value),
      onColorSelected: (value) {
        if (_lassoMode) {
          _setSelectionColor(value);
        } else if (_pointerMode && _selectedObjectId != null) {
          _setSelectedObjectColor(value);
        } else {
          setState(() => _colorValue = value);
        }
      },
      onWidthChanged: (value) {
        if (_pointerMode && _selectedObjectId != null) {
          _setSelectedObjectWidth(value);
        } else {
          setState(() => _width = value);
        }
      },
      onStylusOnlyChanged: (value) => setState(() => _stylusOnly = value),
      onClearActiveLayer: () => unawaited(_clearActiveLayer()),
    );
  }

  Future<void> _onStrokeCompleted(InkStroke stroke) async {
    final layer = _activeLayer;
    if (layer == null || !_canEditActiveLayer) return;
    await widget.inkStore.addStroke(stroke);
    await _layerStore.assignStroke(layer.id, stroke.id);
    if (!mounted) return;
    setState(() {
      _allStrokes = [..._allStrokes.where((s) => s.id != stroke.id), stroke];
      _strokeLayerIds = {..._strokeLayerIds, stroke.id: layer.id};
    });
  }

  Future<void> _onStrokeUpdated(InkStroke stroke) async {
    await widget.inkStore.addStroke(stroke);
    if (!mounted) return;
    setState(() {
      _allStrokes = [
        for (final item in _allStrokes)
          if (item.id == stroke.id) stroke else item,
      ];
    });
  }

  Future<void> _onStrokeErased(InkStroke stroke) async {
    await widget.inkStore.deleteStroke(stroke.id);
    if (!mounted) return;
    setState(() {
      _allStrokes = _allStrokes.where((item) => item.id != stroke.id).toList();
      _strokeLayerIds = {..._strokeLayerIds}..remove(stroke.id);
    });
  }

  Future<void> _showLayers() async {
    if (_currentPage == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> refresh() async {
            await _loadPageContent(
              _currentPage!.id,
              preferredLayerId: _activeLayerId,
            );
            if (mounted) setState(() {});
            setSheetState(() {});
          }

          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Text(
                          'Camadas',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () async {
                            final layer = await _layerStore.createLayer(
                              _currentPage!.id,
                            );
                            _activeLayerId = layer.id;
                            await refresh();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Nova'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _layers.length,
                      onReorderItem: (oldIndex, newIndex) async {
                        final ids = _layers.map((e) => e.id).toList();
                        final moved = ids.removeAt(oldIndex);
                        ids.insert(newIndex, moved);
                        await _layerStore.reorderLayers(_currentPage!.id, ids);
                        await refresh();
                      },
                      itemBuilder: (context, index) {
                        final layer = _layers[index];
                        final active = layer.id == _activeLayerId;
                        final strokeCount = _strokeLayerIds.values
                            .where((id) => id == layer.id)
                            .length;
                        final objectCount = _objectLayerIds.values
                            .where((id) => id == layer.id)
                            .length;
                        return Card(
                          key: ValueKey(layer.id),
                          child: ListTile(
                            selected: active,
                            leading: IconButton(
                              tooltip: layer.isVisible ? 'Ocultar' : 'Mostrar',
                              onPressed: () async {
                                await _layerStore.setVisibility(
                                  layer.id,
                                  !layer.isVisible,
                                );
                                await refresh();
                              },
                              icon: Icon(
                                layer.isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                            title: Text(layer.name),
                            subtitle: Text(
                              '$strokeCount traço(s) • $objectCount objeto(s)',
                            ),
                            onTap: () {
                              _selectLayer(layer.id);
                              setSheetState(() {});
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: layer.isLocked
                                      ? 'Desbloquear'
                                      : 'Bloquear',
                                  onPressed: () async {
                                    await _layerStore.setLocked(
                                      layer.id,
                                      !layer.isLocked,
                                    );
                                    await refresh();
                                  },
                                  icon: Icon(
                                    layer.isLocked
                                        ? Icons.lock
                                        : Icons.lock_open,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'rename') {
                                      await _renameLayer(layer);
                                    }
                                    if (value == 'delete') {
                                      await _deleteLayer(layer);
                                    }
                                    await refresh();
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Renomear'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      enabled: _layers.length > 1,
                                      child: const Text('Excluir'),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.drag_handle),
                              ],
                            ),
                          ),
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

  void _selectLayer(String layerId) {
    if (!_layers.any((layer) => layer.id == layerId)) return;
    setState(() {
      _activeLayerId = layerId;
      _selectionCount = 0;
      _selectedObjectId = null;
      _lassoMode = false;
      _eraserMode = false;
      _pointerMode = false;
      _handMode = false;
    });
    _history.clear();
  }

  Future<void> _renameLayer(NotebookLayer layer) async {
    final controller = TextEditingController(text: layer.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear camada'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await _layerStore.renameLayer(layer.id, value);
    }
  }

  Future<void> _deleteLayer(NotebookLayer layer) async {
    if (_layers.length <= 1) return;
    await _layerStore.deleteLayer(layer.id);
    final remaining = await _layerStore.listLayers(layer.pageId);
    if (_activeLayerId == layer.id) _activeLayerId = remaining.first.id;
  }

  Future<void> _switchNotebook(String id) async {
    final notebook = _notebooks.firstWhere((item) => item.id == id);
    var pages = await widget.inkStore.listPages(id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(id);
      pages = await widget.inkStore.listPages(id);
    }
    final page = pages.first;
    _currentNotebook = notebook;
    _pages = pages;
    _currentPage = page;
    await _loadPageContent(page.id);
    if (mounted) {
      setState(() {
        _selectionCount = 0;
        _selectedObjectId = null;
        _pointerMode = false;
        _handMode = false;
      });
    }
    _history.clear();
  }

  Future<void> _createNotebook() async {
    final controller = TextEditingController(text: 'Novo caderno');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo caderno'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;
    final notebook = await widget.inkStore.createNotebook(title);
    final pages = await widget.inkStore.listPages(notebook.id);
    _currentNotebook = notebook;
    _pages = pages;
    _currentPage = pages.first;
    await _loadPageContent(pages.first.id);
    final notebooks = await widget.inkStore.listNotebooks();
    if (mounted) setState(() => _notebooks = notebooks);
    _history.clear();
  }

  Future<void> _renameNotebook() async {
    final notebook = _currentNotebook;
    if (notebook == null) return;
    final controller = TextEditingController(text: notebook.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear caderno'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    await widget.inkStore.renameNotebook(notebook.id, title);
    await _reloadCurrent();
  }

  Future<void> _deleteNotebook() async {
    final notebook = _currentNotebook;
    if (notebook == null || _notebooks.length <= 1) return;
    await widget.inkStore.deleteNotebook(notebook.id);
    final notebooks = await widget.inkStore.listNotebooks();
    _currentNotebook = notebooks.first;
    _pages = await widget.inkStore.listPages(_currentNotebook!.id);
    _currentPage = _pages.first;
    await _loadPageContent(_currentPage!.id);
    if (mounted) setState(() => _notebooks = notebooks);
    _history.clear();
  }

  Future<void> _openPageAt(int index) async {
    if (index < 0 || index >= _pages.length) return;
    _currentPage = _pages[index];
    await _loadPageContent(_currentPage!.id);
    if (mounted) {
      setState(() {
        _selectionCount = 0;
        _selectedObjectId = null;
        _clipboardAvailable = false;
        _pointerMode = false;
        _handMode = false;
      });
    }
    _history.clear();
  }

  Future<void> _addPage() async {
    final notebook = _currentNotebook;
    if (notebook == null) return;
    final page = await widget.inkStore.createPage(
      notebook.id,
      background: _currentPage?.background ?? InkPageBackground.blank,
    );
    await _reloadCurrent(pageId: page.id);
  }

  Future<void> _duplicatePage() async {
    final page = _currentPage;
    if (page == null) return;
    await _persistRichDocumentNow();
    final duplicate = await widget.inkStore.duplicatePage(page);
    await _objectStore.copyPageObjects(page.id, duplicate.id);
    await _documentStore.copyPageDocument(page.id, duplicate.id);
    await _reloadCurrent(pageId: duplicate.id);
  }

  Future<void> _deletePage() async {
    final page = _currentPage;
    if (page == null || _pages.length <= 1) return;
    final index = _pageIndex;
    await widget.inkStore.deletePage(page.id);
    final pages = await widget.inkStore.listPages(page.notebookId);
    await _reloadCurrent(pageId: pages[index.clamp(0, pages.length - 1)].id);
  }

  Future<void> _movePage(int delta) async {
    final index = _pageIndex;
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _pages.length) return;
    final ids = _pages.map((item) => item.id).toList();
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    await widget.inkStore.reorderPages(_currentNotebook!.id, ids);
    await _reloadCurrent(pageId: moved);
  }

  Future<void> _setBackground(InkPageBackground background) async {
    final page = _currentPage;
    if (page == null) return;
    await widget.inkStore.updatePageBackground(page.id, background);
    await _reloadCurrent(pageId: page.id, preferredLayerId: _activeLayerId);
  }

  String _backgroundLabel(InkPageBackground value) => switch (value) {
    InkPageBackground.blank => 'Branco',
    InkPageBackground.ruled => 'Pautado',
    InkPageBackground.grid => 'Quadriculado',
    InkPageBackground.dotted => 'Pontilhado',
    InkPageBackground.cornell => 'Cornell',
    InkPageBackground.planner => 'Planner',
  };

  Future<void> _persistNewObject(NotebookObject object) async {
    final layer = _activeLayer;
    if (layer == null || !_canEditActiveLayer) return;
    await _objectStore.upsert(object);
    await _layerStore.assignObject(layer.id, object.id);
    if (!mounted) return;
    setState(() {
      _allObjects = [..._allObjects, object];
      _objectLayerIds = {..._objectLayerIds, object.id: layer.id};
      _selectedObjectId = object.id;
    });
  }

  Future<void> _addShape(NotebookObjectType type) async {
    final page = _currentPage;
    if (page == null || !_canEditActiveLayer) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    final linear =
        type == NotebookObjectType.line || type == NotebookObjectType.arrow;
    await _persistNewObject(
      NotebookObject(
        id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
        pageId: page.id,
        type: type,
        x: 80,
        y: 80,
        width: linear ? 180 : 140,
        height: linear ? 80 : 110,
        rotation: 0,
        colorValue: _colorValue,
        strokeWidth: _width.clamp(1, 10),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _addText() async {
    _activateTextMode();
  }

  Future<void> _addImage() async {
    final page = _currentPage;
    if (page == null || !_canEditActiveLayer) return;
    const group = XTypeGroup(
      label: 'Imagens',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    late final String selectedPath;
    late final String selectedName;
    if (Platform.isAndroid) {
      final picked = await const NativeAndroidFilePickerService().pickFile(
        extensions: const ['png', 'jpg', 'jpeg', 'webp'],
        mimeType: 'image/*',
      );
      if (picked == null) return;
      selectedPath = picked.path;
      selectedName = picked.name;
    } else {
      final selected = await openFile(acceptedTypeGroups: const [group]);
      if (selected == null) return;
      selectedPath = selected.path;
      selectedName = selected.name;
    }
    final documents = await getApplicationDocumentsDirectory();
    final assets = Directory(
      '${documents.path}${Platform.pathSeparator}notebook_assets',
    );
    await assets.create(recursive: true);
    final now = DateTime.now().toUtc();
    final safeName =
        selectedName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      '${assets.path}${Platform.pathSeparator}${now.microsecondsSinceEpoch}-$safeName',
    );
    await File(selectedPath).copy(destination.path);
    _recordHistory();
    await _persistNewObject(
      NotebookObject(
        id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
        pageId: page.id,
        type: NotebookObjectType.image,
        x: 70,
        y: 70,
        width: 260,
        height: 190,
        rotation: 0,
        colorValue: 0xFF000000,
        strokeWidth: 1,
        imagePath: destination.path,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  void _activateTextMode() {
    final document = _richDocument;
    if (document == null) return;
    setState(() {
      _textMode = true;
      _pointerMode = false;
      _handMode = false;
      _eraserMode = false;
      _lassoMode = false;
      _selectionCount = 0;
      _selectedObjectId = null;
    });
    _canvasKey.currentState?.clearSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) document.requestEditorFocus();
    });
  }

  Future<void> _copyRichSelection() async {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();
    await executeHandleCopy(document);
    document.requestEditorFocus();
  }

  Future<void> _cutRichSelection() async {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();
    document.saveState(description: 'Cut', forceNewAction: true);
    await executeHandleCut(document);
    document.requestEditorFocus();
  }

  Future<void> _pasteRichSelection() async {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();
    document.saveState(description: 'Paste', forceNewAction: true);
    await executeHandlePaste(document);
    document.requestEditorFocus();
  }

  void _selectAllRichText() {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();
    handleSelectAll(document);
    document.requestEditorFocus();
  }

  void _setSelectedTextStyle({
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    String? fontFamily,
    bool clearFontFamily = false,
    int? colorValue,
    NotebookTextAlign? textAlign,
  }) {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();

    if (bold != null && bold != document.pendingStyles.contains('bold')) {
      document.eventHandler.handleBold();
    }
    if (italic != null && italic != document.pendingStyles.contains('italic')) {
      document.eventHandler.handleItalic();
    }
    if (underline != null &&
        underline != document.pendingStyles.contains('underline')) {
      document.eventHandler.handleUnderline();
    }
    if (fontSize != null) document.eventHandler.handleFontSize(fontSize);
    final resolvedFamily = clearFontFamily
        ? _defaultNotebookFontFamily
        : fontFamily;
    if (resolvedFamily != null)
      document.eventHandler.handleFontFamily(resolvedFamily);
    if (colorValue != null)
      document.eventHandler.handleTextColor(_cssColor(colorValue));
    if (textAlign != null)
      document.eventHandler.handleTextAlign(textAlign.dbValue);
    document.requestEditorFocus();
  }

  Widget _buildTextFormattingToolbar() {
    final selected = _selectedObject;
    final object = selected?.type == NotebookObjectType.text ? selected : null;
    const fontSizes = <double>[10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48];
    const fonts = <String, String>{
      'Arial': 'Arial',
      'Roboto': 'Roboto',
      'Serif': 'serif',
      'Monoespaçada': 'monospace',
    };
    final currentFamily = object?.fontFamily ?? _defaultTextFontFamily;
    final currentSize = object?.fontSize ?? _defaultTextFontSize;
    final currentBold = object?.fontBold ?? _defaultTextBold;
    final currentItalic = object?.fontItalic ?? _defaultTextItalic;
    final currentUnderline = object?.fontUnderline ?? _defaultTextUnderline;
    final currentAlign = object?.textAlign ?? _defaultTextAlign;
    final currentColor = object?.colorValue ?? _defaultTextColorValue;

    Widget alignButton(
      String tooltip,
      IconData icon,
      NotebookTextAlign alignment,
    ) {
      return WordPadCompactIconButton(
        tooltip: tooltip,
        icon: icon,
        selected: currentAlign == alignment,
        onPressed: _canEditActiveLayer
            ? () => _setSelectedTextStyle(textAlign: alignment)
            : null,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Área de transferência',
            minWidth: 178,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Colar',
                  icon: Icons.content_paste,
                  onPressed: _richDocument == null
                      ? null
                      : () => unawaited(_pasteRichSelection()),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordPadCompactIconButton(
                      tooltip: 'Recortar',
                      icon: Icons.content_cut,
                      onPressed: _richDocument == null
                          ? null
                          : () => unawaited(_cutRichSelection()),
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Copiar',
                      icon: Icons.content_copy,
                      onPressed: _richDocument == null
                          ? null
                          : () => unawaited(_copyRichSelection()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Fonte',
            minWidth: 265,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 136,
                      height: 27,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: fonts.containsValue(currentFamily)
                              ? currentFamily
                              : _defaultNotebookFontFamily,
                          isDense: true,
                          isExpanded: true,
                          items: fonts.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.value,
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _canEditActiveLayer
                              ? (family) {
                                  if (family != null) {
                                    _setSelectedTextStyle(fontFamily: family);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 48,
                      height: 27,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: fontSizes.contains(currentSize)
                              ? currentSize
                              : _defaultNotebookFontSize,
                          isDense: true,
                          isExpanded: true,
                          items: fontSizes
                              .map(
                                (size) => DropdownMenuItem(
                                  value: size,
                                  child: Text(
                                    size.toInt().toString(),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _canEditActiveLayer
                              ? (size) {
                                  if (size != null) {
                                    _setSelectedTextStyle(fontSize: size);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Aumentar fonte',
                      icon: Icons.text_increase,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                              fontSize: (currentSize + 2)
                                  .clamp(8, 72)
                                  .toDouble(),
                            )
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Diminuir fonte',
                      icon: Icons.text_decrease,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                              fontSize: (currentSize - 2)
                                  .clamp(8, 72)
                                  .toDouble(),
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordPadCompactIconButton(
                      tooltip: 'Negrito',
                      icon: Icons.format_bold,
                      selected: currentBold,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(bold: !currentBold)
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Itálico',
                      icon: Icons.format_italic,
                      selected: currentItalic,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(italic: !currentItalic)
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Sublinhado',
                      icon: Icons.format_underline,
                      selected: currentUnderline,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                              underline: !currentUnderline,
                            )
                          : null,
                    ),
                    PopupMenuButton<int>(
                      tooltip: 'Cor da fonte',
                      onSelected: (value) =>
                          _setSelectedTextStyle(colorValue: value),
                      itemBuilder: (_) => _palette
                          .map(
                            (value) => PopupMenuItem<int>(
                              value: value,
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    color: Color(value),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value == currentColor
                                        ? 'Cor selecionada'
                                        : 'Usar cor',
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      child: SizedBox(
                        width: 32,
                        height: 27,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.format_color_text, size: 17),
                            Positioned(
                              left: 5,
                              right: 5,
                              bottom: 2,
                              child: Container(
                                height: 3,
                                color: Color(currentColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Parágrafo',
            minWidth: 135,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                alignButton(
                  'Alinhar à esquerda',
                  Icons.format_align_left,
                  NotebookTextAlign.left,
                ),
                alignButton(
                  'Centralizar',
                  Icons.format_align_center,
                  NotebookTextAlign.center,
                ),
                alignButton(
                  'Alinhar à direita',
                  Icons.format_align_right,
                  NotebookTextAlign.right,
                ),
                alignButton(
                  'Justificar',
                  Icons.format_align_justify,
                  NotebookTextAlign.justify,
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Edição',
            minWidth: 190,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Selecionar',
                  icon: Icons.select_all,
                  onPressed: _richDocument == null ? null : _selectAllRichText,
                ),
                WordPadLabeledCommand(
                  label: 'Desfazer',
                  icon: Icons.undo,
                  onPressed: _richDocument == null
                      ? null
                      : () => _richDocument!.undo(),
                ),
                WordPadLabeledCommand(
                  label: 'Refazer',
                  icon: Icons.redo,
                  onPressed: _richDocument == null
                      ? null
                      : () => _richDocument!.redo(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertRibbon() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Páginas',
            minWidth: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Nova página',
                  icon: Icons.note_add_outlined,
                  onPressed: () => unawaited(_addPage()),
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Conteúdo',
            minWidth: 190,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Texto',
                  icon: Icons.text_fields,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(_addText())
                      : null,
                ),
                WordPadLabeledCommand(
                  label: 'Imagem',
                  icon: Icons.image_outlined,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(_addImage())
                      : null,
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Ilustrações',
            minWidth: 155,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Forma',
                  icon: Icons.crop_square_outlined,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(
                            _addShape(NotebookObjectType.rectangle),
                          )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recognizeSelectedInk() async {
    if (!_canEditActiveLayer) return;
    final state = _canvasKey.currentState;
    if (state == null || state.selectedStrokeIds.length != 1) return;
    final stroke = state.strokes.firstWhere(
      (item) => item.id == state.selectedStrokeIds.single,
    );
    final recognition = _shapeRecognizer.recognize(stroke);
    if (recognition == null) return;
    _recordHistory();
    _suppressMutationHistory = true;
    try {
      final now = DateTime.now().toUtc();
      final object = NotebookObject(
        id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
        pageId: stroke.pageId,
        type: recognition.type,
        x: recognition.x,
        y: recognition.y,
        width: recognition.width,
        height: recognition.height,
        rotation: 0,
        colorValue: stroke.colorValue,
        strokeWidth: stroke.width,
        createdAt: now,
        updatedAt: now,
      );
      await _persistNewObject(object);
      final removed = state.deleteSelected();
      for (final item in removed) {
        await _onStrokeErased(item);
      }
      if (mounted) {
        setState(() {
          _lassoMode = false;
          _selectionCount = 0;
          _selectedObjectId = object.id;
          _pointerMode = true;
          _handMode = false;
        });
      }
    } finally {
      _suppressMutationHistory = false;
    }
  }

  void _onObjectChanged(NotebookObject object) {
    if (!_canEditActiveLayer || _objectLayerIds[object.id] != _activeLayerId) {
      return;
    }
    final index = _allObjects.indexWhere((item) => item.id == object.id);
    if (index < 0) return;
    _recordHistory();
    final next = [..._allObjects]..[index] = object;
    setState(() => _allObjects = next);
    unawaited(_objectStore.upsert(object));
  }

  void _rotateSelectedObject(double delta) {
    final object = _selectedObject;
    if (object == null) return;
    final step = math.pi / 12;
    final snapped = ((object.rotation + delta) / step).round() * step;
    _onObjectChanged(
      object.copyWith(rotation: snapped, updatedAt: DateTime.now().toUtc()),
    );
  }

  void _scaleSelectedObject(double factor) {
    final object = _selectedObject;
    if (object == null || factor <= 0) return;
    final nextWidth = math.max(24.0, object.width * factor);
    final nextHeight = math.max(24.0, object.height * factor);
    final nextFontSize = object.fontSize == null
        ? null
        : math.max(8.0, object.fontSize! * factor);
    _onObjectChanged(
      object.copyWith(
        x: object.x + (object.width - nextWidth) / 2,
        y: object.y + (object.height - nextHeight) / 2,
        width: nextWidth,
        height: nextHeight,
        fontSize: nextFontSize,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _duplicateSelectedObject() async {
    final object = _selectedObject;
    if (object == null || !_canEditActiveLayer) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    final duplicate = object.copyWith(
      id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
      x: object.x + 24,
      y: object.y + 24,
      updatedAt: now,
    );
    await _persistNewObject(duplicate);
  }

  void _setSelectedObjectWidth(double value) {
    final object = _selectedObject;
    if (object == null) return;
    _onObjectChanged(
      object.copyWith(
        strokeWidth: value.clamp(1.0, 10.0).toDouble(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _setSelectedObjectColor(int colorValue) {
    final object = _selectedObject;
    if (object == null) return;
    _onObjectChanged(
      object.copyWith(
        colorValue: colorValue,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    setState(() => _colorValue = colorValue);
  }

  Future<void> _deleteSelectedObject() async {
    final id = _selectedObjectId;
    if (id == null || !_canEditActiveLayer) return;
    _recordHistory();
    await _objectStore.delete(id);
    if (!mounted) return;
    setState(() {
      _allObjects = _allObjects.where((item) => item.id != id).toList();
      _objectLayerIds = {..._objectLayerIds}..remove(id);
      _selectedObjectId = null;
    });
  }

  void _moveSelection(double dx, double dy) =>
      _runCanvasMutation(() => _canvasKey.currentState?.moveSelected(dx, dy));

  void _scaleSelection(double factor) =>
      _runCanvasMutation(() => _canvasKey.currentState?.scaleSelected(factor));

  void _rotateSelection(double angleRadians) => _runCanvasMutation(
    () => _canvasKey.currentState?.rotateSelected(angleRadians),
  );

  void _adjustSelectionWidth(double factor) => _runCanvasMutation(
    () => _canvasKey.currentState?.adjustSelectedWidth(factor),
  );

  void _setSelectionColor(int colorValue) {
    if (!_canEditActiveLayer) return;
    _recordHistory();
    _suppressMutationHistory = true;
    final updated =
        _canvasKey.currentState?.updateSelectedColor(colorValue) ?? const [];
    _suppressMutationHistory = false;
    _syncActiveCanvasToState();
    if (updated.isNotEmpty) setState(() => _colorValue = colorValue);
  }

  void _copySelection() {
    final copied = _canvasKey.currentState?.copySelected() ?? const [];
    if (copied.isNotEmpty) setState(() => _clipboardAvailable = true);
  }

  void _duplicateSelection() {
    _runCanvasMutation(() => _canvasKey.currentState?.duplicateSelected());
  }

  void _cutSelection() {
    if (!_canEditActiveLayer) return;
    _recordHistory();
    _suppressMutationHistory = true;
    final removed = _canvasKey.currentState?.cutSelected() ?? const [];
    _suppressMutationHistory = false;
    _syncActiveCanvasToState();
    if (removed.isNotEmpty) {
      setState(() {
        _clipboardAvailable = true;
        _selectionCount = 0;
      });
    }
  }

  void _pasteClipboard() {
    _runCanvasMutation(() => _canvasKey.currentState?.pasteClipboard());
  }

  Future<void> _clearActiveLayer() async {
    final layer = _activeLayer;
    if (layer == null || !_canEditActiveLayer) return;
    _recordHistory();
    final strokeIds = _strokeLayerIds.entries
        .where((e) => e.value == layer.id)
        .map((e) => e.key)
        .toList();
    final legacyTextIds = _allObjects
        .where((object) => object.type == NotebookObjectType.text)
        .map((object) => object.id)
        .toSet();
    final objectIds = _objectLayerIds.entries
        .where((e) => e.value == layer.id && !legacyTextIds.contains(e.key))
        .map((e) => e.key)
        .toList();
    for (final id in strokeIds) {
      await widget.inkStore.deleteStroke(id);
    }
    for (final id in objectIds) {
      await _objectStore.delete(id);
    }
    if (!mounted) return;
    setState(() {
      _allStrokes = _allStrokes
          .where((s) => !strokeIds.contains(s.id))
          .toList();
      _allObjects = _allObjects
          .where((o) => !objectIds.contains(o.id))
          .toList();
      _strokeLayerIds = {..._strokeLayerIds}
        ..removeWhere((k, v) => v == layer.id);
      _objectLayerIds = {..._objectLayerIds}
        ..removeWhere((k, v) => v == layer.id);
      _selectionCount = 0;
      _selectedObjectId = null;
    });
  }
}

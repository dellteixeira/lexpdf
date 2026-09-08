import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/ink_shape_recognizer.dart';
import '../core/notebook/notebook_history.dart';
import '../core/notebook/notebook_object_models.dart';
import '../core/storage/local_ink_store.dart';
import '../core/storage/local_notebook_layer_store.dart';
import '../core/storage/local_notebook_object_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_editor_chrome.dart';
import '../widgets/notebook_editor_toolbar.dart';
import '../widgets/notebook_layer_ink_view.dart';
import '../widgets/notebook_object_layer.dart';
import '../widgets/notebook_page_background.dart';
import '../widgets/notebook_ruler_overlay.dart';

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
  static const InkShapeRecognizer _shapeRecognizer = InkShapeRecognizer();

  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  final NotebookHistoryController _history = NotebookHistoryController();
  final ScrollController _toolbarScrollController = ScrollController();
  final TransformationController _pageTransformController =
      TransformationController();
  late final LocalNotebookObjectStore _objectStore;
  late final LocalNotebookLayerStore _layerStore;
  late final Future<void> _loadFuture;

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
  bool _pointerMode = false;
  bool _rulerMode = false;
  double _zoom = 1.0;
  String? _selectedObjectId;
  bool _suppressMutationHistory = false;

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
    _loadFuture = _loadInitial();
  }

  @override
  void dispose() {
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
      .where((object) => _objectLayerIds[object.id] == _activeLayerId)
      .toList(growable: false);

  List<NotebookObject> get _backgroundObjects => _allObjects
      .where((object) {
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
    });
    _history.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentNotebook?.title ?? 'Cadernos'),
        actions: [
          IconButton(
            tooltip: 'Camadas',
            onPressed: _currentPage == null ? null : _showLayers,
            icon: const Icon(Icons.layers_outlined),
          ),
          IconButton(
            tooltip: 'Novo caderno',
            onPressed: _createNotebook,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opções do caderno',
            onSelected: (value) {
              if (value == 'rename') unawaited(_renameNotebook());
              if (value == 'delete') unawaited(_deleteNotebook());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Renomear caderno')),
              PopupMenuItem(value: 'delete', child: Text('Excluir caderno')),
            ],
          ),
          IconButton(
            tooltip: 'Desfazer',
            onPressed: _history.canUndo ? _undoHistory : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Refazer',
            onPressed: _history.canRedo ? _redoHistory : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
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
          if (page == null)
            return const Center(child: Text('Nenhuma página disponível.'));
          return Column(
            children: [
              _buildNotebookNavigation(),
              const Divider(height: 1),
              _buildLayerStatus(),
              _buildToolbar(),
              const Divider(height: 1),
              Expanded(child: _buildPageViewport(page)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPageViewport(InkNotebookPage page) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _pageTransformController,
              minScale: 0.5,
              maxScale: 4,
              panEnabled: _pointerMode,
              scaleEnabled: _pointerMode,
              boundaryMargin: const EdgeInsets.all(220),
              onInteractionEnd: (_) {
                final scale = _pageTransformController.value
                    .getMaxScaleOnAxis();
                if (mounted) {
                  setState(() => _zoom = scale.clamp(0.5, 4.0));
                }
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: page.width / page.height,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(blurRadius: 12, color: Color(0x22000000)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotebookPageBackground(background: page.background),
                        NotebookLayerInkView(strokes: _backgroundStrokes),
                        NotebookObjectLayer(
                          objects: _backgroundObjects,
                          enabled: false,
                          selectedId: null,
                          onObjectChanged: (_) {},
                          onObjectDoubleTap: (_) {},
                          onSelectionChanged: (_) {},
                        ),
                        IgnorePointer(
                          ignoring: !_canEditActiveLayer || _pointerMode,
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
                          enabled: _pointerMode && _canEditActiveLayer,
                          selectedId: _selectedObjectId,
                          onObjectChanged: _onObjectChanged,
                          onObjectDoubleTap: _handleObjectDoubleTap,
                          onSelectionChanged: (id) {
                            if (mounted) setState(() => _selectedObjectId = id);
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
          Positioned(
            right: 16,
            bottom: 16,
            child: NotebookZoomControls(
              zoom: _zoom,
              onZoomOut: () => _zoomBy(0.85),
              onZoomIn: () => _zoomBy(1.15),
              onReset: _resetZoom,
            ),
          ),
        ],
      ),
    );
  }

  void _zoomBy(double factor) {
    final next = (_zoom * factor).clamp(0.5, 4.0);
    _setZoom(next);
  }

  void _setZoom(double value) {
    final next = value.clamp(0.5, 4.0);
    _pageTransformController.value = Matrix4.diagonal3Values(next, next, 1);
    if (mounted) setState(() => _zoom = next);
  }

  void _resetZoom() {
    _pageTransformController.value = Matrix4.identity();
    if (mounted) setState(() => _zoom = 1.0);
  }

  Widget _buildLayerStatus() {
    final layer = _activeLayer;
    if (layer == null) return const SizedBox.shrink();
    return NotebookLayerStatus(
      layer: layer,
      layerCount: _layers.length,
      onTap: _showLayers,
    );
  }

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
      onMovePageLeft: pageIndex > 0
          ? () => unawaited(_movePage(-1))
          : null,
      onMovePageRight: pageIndex >= 0 && pageIndex < _pages.length - 1
          ? () => unawaited(_movePage(1))
          : null,
      onDeletePage: _pages.length > 1
          ? () => unawaited(_deletePage())
          : null,
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
      tool: _tool,
      eraserMode: _eraserMode,
      lassoMode: _lassoMode,
      clipboardAvailable: _clipboardAvailable,
      selectionCount: _selectionCount,
      rulerMode: _rulerMode,
      palette: _palette,
      colorValue: _colorValue,
      width: _width,
      stylusOnly: _stylusOnly,
      selectedObject: selectedObject,
      onPointerModeChanged: (value) => setState(() {
        _pointerMode = value;
        if (value) {
          _eraserMode = false;
          _lassoMode = false;
          _selectionCount = 0;
        } else {
          _selectedObjectId = null;
        }
      }),
      onToolChanged: (value) => setState(() {
        _tool = value;
        _eraserMode = false;
        _lassoMode = false;
        _pointerMode = false;
        _selectedObjectId = null;
        _selectionCount = 0;
      }),
      onEraserModeChanged: (value) => setState(() {
        _eraserMode = value;
        if (value) {
          _lassoMode = false;
          _pointerMode = false;
          _selectedObjectId = null;
        }
      }),
      onLassoModeChanged: (value) => setState(() {
        _lassoMode = value;
        _eraserMode = false;
        _pointerMode = false;
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
      onRotateObjectLeft: () => _rotateSelectedObject(-_rotationStep),
      onRotateObjectRight: () => _rotateSelectedObject(_rotationStep),
      onEditTextObject: () {
        if (selectedObject != null) unawaited(_editTextObject(selectedObject));
      },
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
      onWidthChanged: (value) => setState(() => _width = value),
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
                                    if (value == 'rename')
                                      await _renameLayer(layer);
                                    if (value == 'delete')
                                      await _deleteLayer(layer);
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
    if (value != null && value.trim().isNotEmpty)
      await _layerStore.renameLayer(layer.id, value);
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
    if (mounted)
      setState(() {
        _selectionCount = 0;
        _selectedObjectId = null;
      });
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
    if (mounted)
      setState(() {
        _selectionCount = 0;
        _selectedObjectId = null;
        _clipboardAvailable = false;
      });
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
    final duplicate = await widget.inkStore.duplicatePage(page);
    await _objectStore.copyPageObjects(page.id, duplicate.id);
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
    final page = _currentPage;
    if (page == null || !_canEditActiveLayer) return;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserir texto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Inserir'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    await _persistNewObject(
      NotebookObject(
        id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
        pageId: page.id,
        type: NotebookObjectType.text,
        x: 80,
        y: 80,
        width: 260,
        height: 100,
        rotation: 0,
        colorValue: _colorValue,
        strokeWidth: 1,
        textValue: value.trim(),
        fontSize: 20,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted)
      setState(() {
        _pointerMode = true;
        _eraserMode = false;
        _lassoMode = false;
      });
  }

  Future<void> _addImage() async {
    final page = _currentPage;
    if (page == null || !_canEditActiveLayer) return;
    const group = XTypeGroup(
      label: 'Imagens',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final selected = await openFile(acceptedTypeGroups: const [group]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    final documents = await getApplicationDocumentsDirectory();
    final assets = Directory(
      '${documents.path}${Platform.pathSeparator}notebook_assets',
    );
    await assets.create(recursive: true);
    final now = DateTime.now().toUtc();
    final safeName = selected.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      '${assets.path}${Platform.pathSeparator}${now.microsecondsSinceEpoch}-$safeName',
    );
    await destination.writeAsBytes(bytes, flush: true);
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

  void _handleObjectDoubleTap(NotebookObject object) {
    if (object.type == NotebookObjectType.text && _canEditActiveLayer)
      unawaited(_editTextObject(object));
  }

  Future<void> _editTextObject(NotebookObject object) async {
    final controller = TextEditingController(text: object.textValue ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar texto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
        ),
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
    if (value == null) return;
    _onObjectChanged(
      object.copyWith(textValue: value, updatedAt: DateTime.now().toUtc()),
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
      if (mounted)
        setState(() {
          _lassoMode = false;
          _selectionCount = 0;
          _selectedObjectId = object.id;
        });
    } finally {
      _suppressMutationHistory = false;
    }
  }

  void _onObjectChanged(NotebookObject object) {
    if (!_canEditActiveLayer || _objectLayerIds[object.id] != _activeLayerId)
      return;
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
    if (removed.isNotEmpty)
      setState(() {
        _clipboardAvailable = true;
        _selectionCount = 0;
      });
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
    final objectIds = _objectLayerIds.entries
        .where((e) => e.value == layer.id)
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

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
import '../core/storage/local_notebook_object_store.dart';
import '../widgets/ink_canvas.dart';
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
  late final LocalNotebookObjectStore _objectStore;
  late final Future<void> _loadFuture;

  List<InkNotebook> _notebooks = const [];
  List<InkNotebookPage> _pages = const [];
  InkNotebook? _currentNotebook;
  InkNotebookPage? _currentPage;
  List<InkStroke> _currentStrokes = const [];
  List<NotebookObject> _objects = const [];

  InkTool _tool = InkTool.pen;
  int _colorValue = 0xFF1C1B1F;
  double _width = 3.0;
  bool _stylusOnly = true;
  bool _eraserMode = false;
  bool _lassoMode = false;
  bool _clipboardAvailable = false;
  int _selectionCount = 0;
  bool _objectMode = false;
  bool _rulerMode = false;
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
    _loadFuture = _loadInitial();
  }

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
    _currentStrokes = await widget.inkStore.listStrokes(target.id);
    _objects = await _objectStore.listObjects(target.id);
    _history.clear();
  }

  NotebookPageSnapshot _captureSnapshot() => NotebookPageSnapshot.capture(
        strokes: _canvasKey.currentState?.strokes ?? _currentStrokes,
        objects: _objects,
      );

  void _recordHistory() {
    if (_suppressMutationHistory || _currentPage == null) return;
    _history.record(_captureSnapshot());
  }

  void _runCanvasMutation(VoidCallback action) {
    _recordHistory();
    _suppressMutationHistory = true;
    try {
      action();
    } finally {
      _suppressMutationHistory = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _restoreSnapshot(NotebookPageSnapshot snapshot) async {
    final page = _currentPage;
    if (page == null) return;
    _suppressMutationHistory = true;
    try {
      await widget.inkStore.replacePageStrokes(page.id, snapshot.strokes);
      await _objectStore.replacePageObjects(page.id, snapshot.objects);
    } finally {
      _suppressMutationHistory = false;
    }
    if (!mounted) return;
    setState(() {
      _currentStrokes = List<InkStroke>.unmodifiable(snapshot.strokes);
      _objects = List<NotebookObject>.unmodifiable(snapshot.objects);
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

  Future<void> _reloadCurrent({String? pageId}) async {
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
    final strokes = await widget.inkStore.listStrokes(target.id);
    final objects = await _objectStore.listObjects(target.id);
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _currentNotebook = currentNotebook;
      _pages = pages;
      _currentPage = target;
      _currentStrokes = strokes;
      _objects = objects;
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
            tooltip: _lassoMode ? 'Sair do laço' : 'Selecionar com laço',
            onPressed: () => setState(() {
              _lassoMode = !_lassoMode;
              _eraserMode = false;
              _objectMode = false;
              _selectedObjectId = null;
              if (!_lassoMode) _selectionCount = 0;
            }),
            icon: Icon(_lassoMode ? Icons.close : Icons.gesture),
            color: _lassoMode ? Theme.of(context).colorScheme.primary : null,
          ),
          if (_lassoMode && _selectionCount > 0)
            IconButton(
              tooltip: 'Excluir $_selectionCount selecionado(s)',
              onPressed: _deleteSelection,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: _eraserMode ? 'Voltar para escrita' : 'Borracha por traço',
            onPressed: () => setState(() {
              _eraserMode = !_eraserMode;
              _lassoMode = false;
              _objectMode = false;
              _selectedObjectId = null;
              _selectionCount = 0;
            }),
            icon: Icon(
              _eraserMode ? Icons.edit_outlined : Icons.auto_fix_normal_outlined,
            ),
            color: _eraserMode ? Theme.of(context).colorScheme.primary : null,
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
              child: Text('Não foi possível abrir o caderno: ${snapshot.error}'),
            );
          }
          final page = _currentPage;
          if (page == null) {
            return const Center(child: Text('Nenhuma página disponível.'));
          }
          return Column(
            children: [
              _buildNotebookNavigation(),
              const Divider(height: 1),
              _buildToolbar(),
              const Divider(height: 1),
              Expanded(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
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
                            InkCanvas(
                              key: _canvasKey,
                              initialStrokes: _currentStrokes,
                              pageId: page.id,
                              tool: _tool,
                              colorValue: _colorValue,
                              strokeWidth: _effectiveWidth,
                              stylusOnly: _stylusOnly,
                              eraserMode: _eraserMode,
                              lassoMode: _lassoMode,
                              onStrokeCompleted: (stroke) {
                                if (!_suppressMutationHistory) _recordHistory();
                                unawaited(widget.inkStore.addStroke(stroke));
                                setState(() {});
                              },
                              onStrokeUpdated: (stroke) {
                                unawaited(widget.inkStore.addStroke(stroke));
                              },
                              onStrokeErased: (stroke) {
                                if (!_suppressMutationHistory) _recordHistory();
                                unawaited(widget.inkStore.deleteStroke(stroke.id));
                                setState(() {});
                              },
                              onSelectionChanged: (ids) {
                                if (!mounted) return;
                                setState(() => _selectionCount = ids.length);
                              },
                            ),
                            NotebookObjectLayer(
                              objects: _objects,
                              enabled: _objectMode,
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotebookNavigation() {
    final notebook = _currentNotebook;
    final page = _currentPage;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            DropdownButton<String>(
              value: notebook?.id,
              items: _notebooks
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.title),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (id) {
                if (id != null) unawaited(_switchNotebook(id));
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Página anterior',
              onPressed: _pageIndex > 0 ? () => _openPageAt(_pageIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Página ${page?.pageNumber ?? 0} de ${_pages.length}'),
            IconButton(
              tooltip: 'Próxima página',
              onPressed: _pageIndex >= 0 && _pageIndex < _pages.length - 1
                  ? () => _openPageAt(_pageIndex + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Adicionar página',
              onPressed: _addPage,
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              tooltip: 'Duplicar página',
              onPressed: page == null ? null : _duplicatePage,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: 'Mover página para a esquerda',
              onPressed: _pageIndex > 0 ? () => _movePage(-1) : null,
              icon: const Icon(Icons.keyboard_double_arrow_left),
            ),
            IconButton(
              tooltip: 'Mover página para a direita',
              onPressed: _pageIndex >= 0 && _pageIndex < _pages.length - 1
                  ? () => _movePage(1)
                  : null,
              icon: const Icon(Icons.keyboard_double_arrow_right),
            ),
            IconButton(
              tooltip: 'Excluir página',
              onPressed: _pages.length > 1 ? _deletePage : null,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 12),
            DropdownButton<InkPageBackground>(
              value: page?.background,
              hint: const Text('Template'),
              items: InkPageBackground.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_backgroundLabel(value)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) unawaited(_setBackground(value));
              },
            ),
          ],
        ),
      ),
    );
  }

  int get _pageIndex => _pages.indexWhere((item) => item.id == _currentPage?.id);

  double get _effectiveWidth => switch (_tool) {
        InkTool.pen => _width,
        InkTool.pencil => _width * 0.8,
        InkTool.highlighter => _width * 5,
      };

  NotebookObject? get _selectedObject {
    final id = _selectedObjectId;
    if (id == null) return null;
    for (final object in _objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  Widget _buildToolbar() {
    final selectedObject = _selectedObject;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SegmentedButton<InkTool>(
              segments: const [
                ButtonSegment(value: InkTool.pen, icon: Icon(Icons.edit_outlined), label: Text('Caneta')),
                ButtonSegment(value: InkTool.pencil, icon: Icon(Icons.draw_outlined), label: Text('Lápis')),
                ButtonSegment(value: InkTool.highlighter, icon: Icon(Icons.border_color_outlined), label: Text('Marca-texto')),
              ],
              selected: {_tool},
              onSelectionChanged: (selection) => setState(() {
                _tool = selection.first;
                _eraserMode = false;
                _lassoMode = false;
                _objectMode = false;
                _selectedObjectId = null;
                _selectionCount = 0;
              }),
            ),
            const SizedBox(width: 12),
            FilterChip(
              selected: _eraserMode,
              avatar: const Icon(Icons.auto_fix_normal_outlined, size: 18),
              label: const Text('Borracha'),
              onSelected: (value) => setState(() {
                _eraserMode = value;
                if (value) {
                  _lassoMode = false;
                  _objectMode = false;
                  _selectedObjectId = null;
                  _selectionCount = 0;
                }
              }),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _lassoMode,
              avatar: const Icon(Icons.gesture, size: 18),
              label: Text(_selectionCount > 0 ? 'Laço ($_selectionCount)' : 'Laço'),
              onSelected: (value) => setState(() {
                _lassoMode = value;
                _eraserMode = false;
                _objectMode = false;
                _selectedObjectId = null;
                if (!value) _selectionCount = 0;
              }),
            ),
            if (_lassoMode && _selectionCount > 0) ..._buildLassoTools(),
            if (_lassoMode && _clipboardAvailable)
              IconButton(
                tooltip: 'Colar',
                onPressed: _pasteClipboard,
                icon: const Icon(Icons.content_paste),
              ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _objectMode,
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: const Text('Objetos'),
              onSelected: (value) => setState(() {
                _objectMode = value;
                _lassoMode = false;
                _eraserMode = false;
                _selectionCount = 0;
                if (!value) _selectedObjectId = null;
              }),
            ),
            if (_objectMode) ...[
              PopupMenuButton<NotebookObjectType>(
                tooltip: 'Inserir forma',
                icon: const Icon(Icons.add_box_outlined),
                onSelected: _addShape,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: NotebookObjectType.line, child: Text('Linha')),
                  PopupMenuItem(value: NotebookObjectType.arrow, child: Text('Seta')),
                  PopupMenuItem(value: NotebookObjectType.rectangle, child: Text('Retângulo')),
                  PopupMenuItem(value: NotebookObjectType.ellipse, child: Text('Elipse')),
                  PopupMenuItem(value: NotebookObjectType.triangle, child: Text('Triângulo')),
                ],
              ),
              IconButton(tooltip: 'Inserir texto', onPressed: _addText, icon: const Icon(Icons.text_fields)),
              IconButton(tooltip: 'Inserir imagem', onPressed: _addImage, icon: const Icon(Icons.add_photo_alternate_outlined)),
              if (selectedObject != null) ...[
                IconButton(tooltip: 'Girar objeto 15° à esquerda', onPressed: () => _rotateSelectedObject(-_rotationStep), icon: const Icon(Icons.rotate_left)),
                IconButton(tooltip: 'Girar objeto 15° à direita', onPressed: () => _rotateSelectedObject(_rotationStep), icon: const Icon(Icons.rotate_right)),
                if (selectedObject.type == NotebookObjectType.text) ...[
                  IconButton(tooltip: 'Editar texto', onPressed: () => _editTextObject(selectedObject), icon: const Icon(Icons.edit_note)),
                  IconButton(tooltip: 'Diminuir fonte', onPressed: () => _adjustSelectedTextSize(-2), icon: const Icon(Icons.text_decrease)),
                  IconButton(tooltip: 'Aumentar fonte', onPressed: () => _adjustSelectedTextSize(2), icon: const Icon(Icons.text_increase)),
                ],
                IconButton(tooltip: 'Excluir objeto', onPressed: _deleteSelectedObject, icon: const Icon(Icons.delete_outline)),
              ],
            ],
            const SizedBox(width: 8),
            FilterChip(
              selected: _rulerMode,
              avatar: const Icon(Icons.straighten, size: 18),
              label: const Text('Régua'),
              onSelected: (value) => setState(() => _rulerMode = value),
            ),
            const SizedBox(width: 16),
            for (final value in _palette)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _eraserMode || (_lassoMode && _selectionCount == 0)
                      ? null
                      : () {
                          if (_lassoMode) {
                            _setSelectionColor(value);
                          } else if (_objectMode && _selectedObjectId != null) {
                            _setSelectedObjectColor(value);
                          } else {
                            setState(() => _colorValue = value);
                          }
                        },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorValue == value
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                        width: _colorValue == value ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 16),
            const Text('Espessura'),
            SizedBox(
              width: 150,
              child: Slider(
                min: 1,
                max: 10,
                value: _width,
                onChanged: _eraserMode || _lassoMode || _objectMode
                    ? null
                    : (value) => setState(() => _width = value),
              ),
            ),
            FilterChip(
              selected: _stylusOnly,
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Somente caneta'),
              onSelected: (value) => setState(() => _stylusOnly = value),
            ),
            IconButton(tooltip: 'Limpar página', onPressed: _clearPage, icon: const Icon(Icons.delete_sweep_outlined)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLassoTools() => [
        const SizedBox(width: 8),
        const Text('Mover'),
        IconButton(onPressed: () => _moveSelection(-_moveStep, 0), icon: const Icon(Icons.arrow_left)),
        IconButton(onPressed: () => _moveSelection(0, -_moveStep), icon: const Icon(Icons.arrow_upward)),
        IconButton(onPressed: () => _moveSelection(0, _moveStep), icon: const Icon(Icons.arrow_downward)),
        IconButton(onPressed: () => _moveSelection(_moveStep, 0), icon: const Icon(Icons.arrow_right)),
        const Text('Tamanho'),
        IconButton(onPressed: () => _scaleSelection(_scaleDown), icon: const Icon(Icons.zoom_in_map)),
        IconButton(onPressed: () => _scaleSelection(_scaleUp), icon: const Icon(Icons.zoom_out_map)),
        const Text('Girar'),
        IconButton(onPressed: () => _rotateSelection(-_rotationStep), icon: const Icon(Icons.rotate_left)),
        IconButton(onPressed: () => _rotateSelection(_rotationStep), icon: const Icon(Icons.rotate_right)),
        const Text('Traço'),
        IconButton(onPressed: () => _adjustSelectionWidth(_widthDown), icon: const Icon(Icons.remove)),
        IconButton(onPressed: () => _adjustSelectionWidth(_widthUp), icon: const Icon(Icons.add)),
        IconButton(tooltip: 'Copiar', onPressed: _copySelection, icon: const Icon(Icons.content_copy)),
        IconButton(tooltip: 'Duplicar', onPressed: _duplicateSelection, icon: const Icon(Icons.copy_all_outlined)),
        IconButton(tooltip: 'Recortar', onPressed: _cutSelection, icon: const Icon(Icons.content_cut)),
        IconButton(tooltip: 'Reconhecer forma do traço', onPressed: _recognizeSelectedInk, icon: const Icon(Icons.auto_awesome_outlined)),
      ];

  Future<void> _switchNotebook(String id) async {
    final notebook = _notebooks.firstWhere((item) => item.id == id);
    var pages = await widget.inkStore.listPages(id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(id);
      pages = await widget.inkStore.listPages(id);
    }
    final page = pages.first;
    final strokes = await widget.inkStore.listStrokes(page.id);
    final objects = await _objectStore.listObjects(page.id);
    if (!mounted) return;
    setState(() {
      _currentNotebook = notebook;
      _pages = pages;
      _currentPage = page;
      _currentStrokes = strokes;
      _objects = objects;
      _selectionCount = 0;
      _clipboardAvailable = false;
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Criar')),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;
    final notebook = await widget.inkStore.createNotebook(title);
    final pages = await widget.inkStore.listPages(notebook.id);
    final page = pages.first;
    final strokes = await widget.inkStore.listStrokes(page.id);
    if (!mounted) return;
    setState(() {
      _notebooks = [..._notebooks, notebook];
      _currentNotebook = notebook;
      _pages = pages;
      _currentPage = page;
      _currentStrokes = strokes;
      _objects = const [];
      _selectedObjectId = null;
    });
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Salvar')),
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
    final next = notebooks.first;
    var pages = await widget.inkStore.listPages(next.id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(next.id);
      pages = await widget.inkStore.listPages(next.id);
    }
    final page = pages.first;
    final strokes = await widget.inkStore.listStrokes(page.id);
    final objects = await _objectStore.listObjects(page.id);
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _currentNotebook = next;
      _pages = pages;
      _currentPage = page;
      _currentStrokes = strokes;
      _objects = objects;
      _selectedObjectId = null;
    });
    _history.clear();
  }

  Future<void> _openPageAt(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    final strokes = await widget.inkStore.listStrokes(page.id);
    final objects = await _objectStore.listObjects(page.id);
    if (!mounted) return;
    setState(() {
      _currentPage = page;
      _currentStrokes = strokes;
      _objects = objects;
      _selectionCount = 0;
      _clipboardAvailable = false;
      _selectedObjectId = null;
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
    final safeIndex = index.clamp(0, pages.length - 1).toInt();
    await _reloadCurrent(pageId: pages[safeIndex].id);
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
    await _reloadCurrent(pageId: page.id);
  }

  String _backgroundLabel(InkPageBackground value) => switch (value) {
        InkPageBackground.blank => 'Branco',
        InkPageBackground.ruled => 'Pautado',
        InkPageBackground.grid => 'Quadriculado',
        InkPageBackground.dotted => 'Pontilhado',
        InkPageBackground.cornell => 'Cornell',
        InkPageBackground.planner => 'Planner',
      };

  Future<void> _addShape(NotebookObjectType type) async {
    final page = _currentPage;
    if (page == null) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    final isLinear = type == NotebookObjectType.line || type == NotebookObjectType.arrow;
    final object = NotebookObject(
      id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
      pageId: page.id,
      type: type,
      x: 80,
      y: 80,
      width: isLinear ? 180 : 140,
      height: isLinear ? 80 : 110,
      rotation: 0,
      colorValue: _colorValue,
      strokeWidth: _width.clamp(1, 10),
      createdAt: now,
      updatedAt: now,
    );
    await _objectStore.upsert(object);
    if (!mounted) return;
    setState(() {
      _objects = [..._objects, object];
      _selectedObjectId = object.id;
    });
  }

  Future<void> _addText() async {
    final page = _currentPage;
    if (page == null) return;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserir texto'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5, decoration: const InputDecoration(hintText: 'Digite o texto')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Inserir')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    final object = NotebookObject(
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
    );
    await _objectStore.upsert(object);
    if (!mounted) return;
    setState(() {
      _objects = [..._objects, object];
      _selectedObjectId = object.id;
    });
  }

  Future<void> _addImage() async {
    final page = _currentPage;
    if (page == null) return;
    const group = XTypeGroup(label: 'Imagens', extensions: ['png', 'jpg', 'jpeg', 'webp']);
    final selected = await openFile(acceptedTypeGroups: const [group]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    final documents = await getApplicationDocumentsDirectory();
    final assets = Directory('${documents.path}${Platform.pathSeparator}notebook_assets');
    await assets.create(recursive: true);
    final now = DateTime.now().toUtc();
    final safeName = selected.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File('${assets.path}${Platform.pathSeparator}${now.microsecondsSinceEpoch}-$safeName');
    await destination.writeAsBytes(bytes, flush: true);
    _recordHistory();
    final object = NotebookObject(
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
    );
    await _objectStore.upsert(object);
    if (!mounted) return;
    setState(() {
      _objects = [..._objects, object];
      _selectedObjectId = object.id;
    });
  }

  void _handleObjectDoubleTap(NotebookObject object) {
    if (object.type == NotebookObjectType.text) unawaited(_editTextObject(object));
  }

  Future<void> _editTextObject(NotebookObject object) async {
    final controller = TextEditingController(text: object.textValue ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar texto'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    _onObjectChanged(object.copyWith(textValue: value, updatedAt: DateTime.now().toUtc()));
  }

  void _adjustSelectedTextSize(double delta) {
    final object = _selectedObject;
    if (object == null || object.type != NotebookObjectType.text) return;
    final current = object.fontSize ?? 20;
    _onObjectChanged(
      object.copyWith(
        fontSize: (current + delta).clamp(8, 96).toDouble(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _recognizeSelectedInk() async {
    final state = _canvasKey.currentState;
    if (state == null) return;
    final ids = state.selectedStrokeIds;
    if (ids.length != 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione apenas um traço para reconhecer a forma.')),
        );
      }
      return;
    }
    final stroke = state.strokes.firstWhere((item) => item.id == ids.single);
    final recognition = _shapeRecognizer.recognize(stroke);
    if (recognition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O traço não corresponde a uma forma reconhecível.')),
        );
      }
      return;
    }
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
      await _objectStore.upsert(object);
      final removed = state.deleteSelected();
      for (final item in removed) {
        await widget.inkStore.deleteStroke(item.id);
      }
      if (!mounted) return;
      setState(() {
        _objects = [..._objects, object];
        _objectMode = true;
        _lassoMode = false;
        _selectionCount = 0;
        _selectedObjectId = object.id;
      });
    } finally {
      _suppressMutationHistory = false;
    }
  }

  void _onObjectChanged(NotebookObject object) {
    final index = _objects.indexWhere((item) => item.id == object.id);
    if (index < 0) return;
    _recordHistory();
    final next = [..._objects]..[index] = object;
    setState(() => _objects = next);
    unawaited(_objectStore.upsert(object));
  }

  void _rotateSelectedObject(double delta) {
    final object = _selectedObject;
    if (object == null) return;
    final step = math.pi / 12;
    final raw = object.rotation + delta;
    final snapped = (raw / step).round() * step;
    _onObjectChanged(object.copyWith(rotation: snapped, updatedAt: DateTime.now().toUtc()));
  }

  void _setSelectedObjectColor(int colorValue) {
    final object = _selectedObject;
    if (object == null) return;
    _onObjectChanged(object.copyWith(colorValue: colorValue, updatedAt: DateTime.now().toUtc()));
    setState(() => _colorValue = colorValue);
  }

  Future<void> _deleteSelectedObject() async {
    final id = _selectedObjectId;
    if (id == null) return;
    _recordHistory();
    await _objectStore.delete(id);
    if (!mounted) return;
    setState(() {
      _objects = _objects.where((item) => item.id != id).toList(growable: false);
      _selectedObjectId = null;
    });
  }

  void _moveSelection(double dx, double dy) =>
      _runCanvasMutation(() => _canvasKey.currentState?.moveSelected(dx, dy));
  void _scaleSelection(double factor) =>
      _runCanvasMutation(() => _canvasKey.currentState?.scaleSelected(factor));
  void _rotateSelection(double angleRadians) =>
      _runCanvasMutation(() => _canvasKey.currentState?.rotateSelected(angleRadians));
  void _adjustSelectionWidth(double factor) =>
      _runCanvasMutation(() => _canvasKey.currentState?.adjustSelectedWidth(factor));

  void _setSelectionColor(int colorValue) {
    _recordHistory();
    _suppressMutationHistory = true;
    final updated = _canvasKey.currentState?.updateSelectedColor(colorValue) ?? const [];
    _suppressMutationHistory = false;
    if (updated.isNotEmpty) setState(() => _colorValue = colorValue);
  }

  void _copySelection() {
    final copied = _canvasKey.currentState?.copySelected() ?? const [];
    if (copied.isNotEmpty) setState(() => _clipboardAvailable = true);
  }

  void _duplicateSelection() =>
      _runCanvasMutation(() => _canvasKey.currentState?.duplicateSelected());

  void _cutSelection() {
    _recordHistory();
    _suppressMutationHistory = true;
    final removed = _canvasKey.currentState?.cutSelected() ?? const [];
    _suppressMutationHistory = false;
    if (removed.isNotEmpty) {
      setState(() {
        _clipboardAvailable = true;
        _selectionCount = 0;
      });
    }
  }

  void _pasteClipboard() =>
      _runCanvasMutation(() => _canvasKey.currentState?.pasteClipboard());

  Future<void> _deleteSelection() async {
    _recordHistory();
    _suppressMutationHistory = true;
    try {
      final removed = _canvasKey.currentState?.deleteSelected() ?? const [];
      for (final stroke in removed) {
        await widget.inkStore.deleteStroke(stroke.id);
      }
    } finally {
      _suppressMutationHistory = false;
    }
    if (mounted) setState(() => _selectionCount = 0);
  }

  Future<void> _clearPage() async {
    final page = _currentPage;
    if (page == null) return;
    _recordHistory();
    _suppressMutationHistory = true;
    try {
      await widget.inkStore.clearPage(page.id);
      await _objectStore.clearPage(page.id);
      _canvasKey.currentState?.clear();
    } finally {
      _suppressMutationHistory = false;
    }
    if (mounted) {
      setState(() {
        _currentStrokes = const [];
        _objects = const [];
        _selectionCount = 0;
        _clipboardAvailable = false;
        _selectedObjectId = null;
      });
    }
  }
}

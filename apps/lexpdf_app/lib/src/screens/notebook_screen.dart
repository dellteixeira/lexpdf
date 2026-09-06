import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_page_background.dart';

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

  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  late Future<void> _loadFuture = _loadInitial();

  List<InkNotebook> _notebooks = const [];
  List<InkNotebookPage> _pages = const [];
  InkNotebook? _currentNotebook;
  InkNotebookPage? _currentPage;
  List<InkStroke> _currentStrokes = const [];

  InkTool _tool = InkTool.pen;
  int _colorValue = 0xFF1C1B1F;
  double _width = 3.0;
  bool _stylusOnly = true;
  bool _eraserMode = false;
  bool _lassoMode = false;
  bool _clipboardAvailable = false;
  int _selectionCount = 0;

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

  Future<void> _loadInitial() async {
    final page = await widget.inkStore.ensureDefaultPage();
    final notebooks = await widget.inkStore.listNotebooks();
    final notebook = notebooks.firstWhere(
      (item) => item.id == page.notebookId,
      orElse: () => notebooks.first,
    );
    final pages = await widget.inkStore.listPages(notebook.id);
    await _setSession(notebook, pages.firstWhere((item) => item.id == page.id));
  }

  Future<void> _setSession(InkNotebook notebook, InkNotebookPage page) async {
    final pages = await widget.inkStore.listPages(notebook.id);
    final strokes = await widget.inkStore.listStrokes(page.id);
    if (!mounted && _currentNotebook != null) return;
    _notebooks = await widget.inkStore.listNotebooks();
    _currentNotebook = notebook;
    _pages = pages;
    _currentPage = page;
    _currentStrokes = strokes;
    _selectionCount = 0;
    _lassoMode = false;
    _eraserMode = false;
    _clipboardAvailable = false;
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
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _currentNotebook = currentNotebook;
      _pages = pages;
      _currentPage = target;
      _currentStrokes = strokes;
      _selectionCount = 0;
      _lassoMode = false;
      _eraserMode = false;
      _clipboardAvailable = false;
    });
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
              _selectionCount = 0;
            }),
            icon: Icon(
              _eraserMode ? Icons.edit_outlined : Icons.auto_fix_normal_outlined,
            ),
            color: _eraserMode ? Theme.of(context).colorScheme.primary : null,
          ),
          IconButton(
            tooltip: 'Desfazer último traço',
            onPressed: _undo,
            icon: const Icon(Icons.undo),
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
            return Center(child: Text('Não foi possível abrir o caderno: ${snapshot.error}'));
          }
          final page = _currentPage;
          if (page == null) return const Center(child: Text('Nenhuma página disponível.'));
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
                              key: ValueKey('ink-${page.id}'),
                              initialStrokes: _currentStrokes,
                              pageId: page.id,
                              tool: _tool,
                              colorValue: _colorValue,
                              strokeWidth: _effectiveWidth,
                              stylusOnly: _stylusOnly,
                              eraserMode: _eraserMode,
                              lassoMode: _lassoMode,
                              onStrokeCompleted: (stroke) {
                                unawaited(widget.inkStore.addStroke(stroke));
                              },
                              onStrokeUpdated: (stroke) {
                                unawaited(widget.inkStore.addStroke(stroke));
                              },
                              onStrokeErased: (stroke) {
                                unawaited(widget.inkStore.deleteStroke(stroke.id));
                              },
                              onSelectionChanged: (ids) {
                                if (!mounted) return;
                                setState(() => _selectionCount = ids.length);
                              },
                            ),
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
                  .map((item) => DropdownMenuItem(value: item.id, child: Text(item.title)))
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

  Widget _buildToolbar() {
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
                if (!value) _selectionCount = 0;
              }),
            ),
            if (_lassoMode && _selectionCount > 0) ...[
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
            ],
            if (_lassoMode && _clipboardAvailable)
              IconButton(tooltip: 'Colar', onPressed: _pasteClipboard, icon: const Icon(Icons.content_paste)),
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
                onChanged: _eraserMode || _lassoMode ? null : (value) => setState(() => _width = value),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _stylusOnly,
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Somente caneta'),
              onSelected: (value) => setState(() => _stylusOnly = value),
            ),
            IconButton(
              tooltip: 'Limpar página',
              onPressed: _clearPage,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchNotebook(String id) async {
    final notebook = _notebooks.firstWhere((item) => item.id == id);
    final pages = await widget.inkStore.listPages(id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(id);
    }
    final resolvedPages = await widget.inkStore.listPages(id);
    final strokes = await widget.inkStore.listStrokes(resolvedPages.first.id);
    if (!mounted) return;
    setState(() {
      _currentNotebook = notebook;
      _pages = resolvedPages;
      _currentPage = resolvedPages.first;
      _currentStrokes = strokes;
      _selectionCount = 0;
      _clipboardAvailable = false;
    });
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
    final strokes = await widget.inkStore.listStrokes(pages.first.id);
    if (!mounted) return;
    setState(() {
      _notebooks = [..._notebooks, notebook];
      _currentNotebook = notebook;
      _pages = pages;
      _currentPage = pages.first;
      _currentStrokes = strokes;
    });
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
    final pages = await widget.inkStore.listPages(next.id);
    final strokes = await widget.inkStore.listStrokes(pages.first.id);
    if (!mounted) return;
    setState(() {
      _notebooks = notebooks;
      _currentNotebook = next;
      _pages = pages;
      _currentPage = pages.first;
      _currentStrokes = strokes;
    });
  }

  Future<void> _openPageAt(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    final strokes = await widget.inkStore.listStrokes(page.id);
    if (!mounted) return;
    setState(() {
      _currentPage = page;
      _currentStrokes = strokes;
      _selectionCount = 0;
      _clipboardAvailable = false;
    });
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
    await _reloadCurrent(pageId: duplicate.id);
  }

  Future<void> _deletePage() async {
    final page = _currentPage;
    if (page == null || _pages.length <= 1) return;
    final index = _pageIndex;
    await widget.inkStore.deletePage(page.id);
    final pages = await widget.inkStore.listPages(page.notebookId);
    final target = pages[index.clamp(0, pages.length - 1)];
    await _reloadCurrent(pageId: target.id);
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

  void _moveSelection(double dx, double dy) => _canvasKey.currentState?.moveSelected(dx, dy);
  void _scaleSelection(double factor) => _canvasKey.currentState?.scaleSelected(factor);
  void _rotateSelection(double angleRadians) => _canvasKey.currentState?.rotateSelected(angleRadians);
  void _adjustSelectionWidth(double factor) => _canvasKey.currentState?.adjustSelectedWidth(factor);

  void _setSelectionColor(int colorValue) {
    final updated = _canvasKey.currentState?.updateSelectedColor(colorValue) ?? const [];
    if (updated.isNotEmpty) setState(() => _colorValue = colorValue);
  }

  void _copySelection() {
    final copied = _canvasKey.currentState?.copySelected() ?? const [];
    if (copied.isNotEmpty) setState(() => _clipboardAvailable = true);
  }

  void _duplicateSelection() => _canvasKey.currentState?.duplicateSelected();

  void _cutSelection() {
    final removed = _canvasKey.currentState?.cutSelected() ?? const [];
    if (removed.isNotEmpty) {
      setState(() {
        _clipboardAvailable = true;
        _selectionCount = 0;
      });
    }
  }

  void _pasteClipboard() => _canvasKey.currentState?.pasteClipboard();

  Future<void> _deleteSelection() async {
    final removed = _canvasKey.currentState?.deleteSelected() ?? const [];
    for (final stroke in removed) {
      await widget.inkStore.deleteStroke(stroke.id);
    }
    if (mounted) setState(() => _selectionCount = 0);
  }

  Future<void> _undo() async {
    final removed = _canvasKey.currentState?.undoLast();
    if (removed != null) await widget.inkStore.deleteStroke(removed.id);
  }

  Future<void> _clearPage() async {
    final page = _currentPage;
    if (page == null) return;
    await widget.inkStore.clearPage(page.id);
    _canvasKey.currentState?.clear();
    if (mounted) {
      setState(() {
        _currentStrokes = const [];
        _selectionCount = 0;
        _clipboardAvailable = false;
      });
    }
  }
}

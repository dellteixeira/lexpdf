import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_paper.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_page_background.dart';

enum _NotebookTool { pen, pencil, highlighter, eraser, lasso, hand }

class StylusNotebookEditorScreen extends StatefulWidget {
  const StylusNotebookEditorScreen({
    required this.inkStore,
    required this.notebook,
    super.key,
  });

  final LocalInkStore inkStore;
  final InkNotebook notebook;

  @override
  State<StylusNotebookEditorScreen> createState() =>
      _StylusNotebookEditorScreenState();
}

class _StylusNotebookEditorScreenState
    extends State<StylusNotebookEditorScreen> {
  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  final TransformationController _transform = TransformationController();

  List<InkNotebookPage> _pages = const [];
  List<InkStroke> _strokes = const [];
  InkNotebookPage? _page;
  _NotebookTool _tool = _NotebookTool.pen;
  int _colorValue = 0xFF1E1E1E;
  double _width = 3.2;
  bool _stylusOnly = true;
  bool _loading = true;
  int _selectionCount = 0;
  String? _fitPageId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load({String? selectPageId}) async {
    var pages = await widget.inkStore.listPages(widget.notebook.id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(widget.notebook.id);
      pages = await widget.inkStore.listPages(widget.notebook.id);
    }

    final selected = selectPageId == null
        ? pages.first
        : pages.firstWhere(
            (page) => page.id == selectPageId,
            orElse: () => pages.first,
          );
    final strokes = await widget.inkStore.listStrokes(selected.id);
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _page = selected;
      _strokes = strokes;
      _loading = false;
      _selectionCount = 0;
      _fitPageId = null;
    });
  }

  Future<void> _openPage(InkNotebookPage page) async {
    if (_page?.id == page.id) return;
    final strokes = await widget.inkStore.listStrokes(page.id);
    if (!mounted) return;
    setState(() {
      _page = page;
      _strokes = strokes;
      _selectionCount = 0;
      _fitPageId = null;
    });
  }

  Future<void> _addPage() async {
    final current = _page;
    if (current == null) return;
    final page = await widget.inkStore.createPage(
      widget.notebook.id,
      background: current.background,
      width: current.width,
      height: current.height,
    );
    await _load(selectPageId: page.id);
  }

  Future<void> _duplicatePage() async {
    final current = _page;
    if (current == null) return;
    final page = await widget.inkStore.duplicatePage(current);
    await _load(selectPageId: page.id);
  }

  Future<void> _deletePage() async {
    final current = _page;
    if (current == null || _pages.length <= 1) return;
    final index = _pages.indexWhere((page) => page.id == current.id);
    await widget.inkStore.deletePage(current.id);
    final pages = await widget.inkStore.listPages(widget.notebook.id);
    final next = pages[math.min(index, pages.length - 1)];
    await _load(selectPageId: next.id);
  }

  Future<void> _clearPage() async {
    final current = _page;
    if (current == null || _strokes.isEmpty) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Limpar página?'),
            content: const Text('Todos os traços desta página serão apagados.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Limpar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.inkStore.clearPage(current.id);
    _canvasKey.currentState?.clear();
    if (mounted) setState(() => _strokes = const []);
  }

  Future<void> _undo() async {
    final removed = _canvasKey.currentState?.undoLast();
    if (removed == null) return;
    await widget.inkStore.deleteStroke(removed.id);
    if (mounted) {
      setState(() {
        _strokes = _canvasKey.currentState?.strokes ?? const [];
      });
    }
  }

  InkTool get _inkTool => switch (_tool) {
        _NotebookTool.pencil => InkTool.pencil,
        _NotebookTool.highlighter => InkTool.highlighter,
        _ => InkTool.pen,
      };

  bool get _eraser => _tool == _NotebookTool.eraser;
  bool get _lasso => _tool == _NotebookTool.lasso;
  bool get _hand => _tool == _NotebookTool.hand;

  void _selectTool(_NotebookTool tool) {
    setState(() {
      _tool = tool;
      if (tool != _NotebookTool.lasso) _selectionCount = 0;
    });
  }

  Future<void> _showPenSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          const colors = <int>[
            0xFF1E1E1E,
            0xFF246BFD,
            0xFFD93025,
            0xFF188038,
            0xFF7B1FA2,
            0xFFFF8F00,
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Caneta', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in colors)
                        InkWell(
                          onTap: () {
                            setState(() => _colorValue = color);
                            setSheetState(() {});
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _colorValue == color
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Espessura: ${_width.toStringAsFixed(1)}'),
                  Slider(
                    value: _width,
                    min: 1,
                    max: 18,
                    divisions: 34,
                    onChanged: (value) {
                      setState(() => _width = value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Somente caneta/stylus escreve'),
                    subtitle: const Text(
                      'Recomendado para rejeição de palma no Samsung S Pen.',
                    ),
                    value: _stylusOnly,
                    onChanged: (value) {
                      setState(() => _stylusOnly = value);
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showPageSettings() async {
    final current = _page;
    if (current == null) return;
    var background = current.background;
    var size = NotebookPaperSize.infer(current.width, current.height);
    var landscape = !size.isInfinite && current.width > current.height;

    final apply = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Configurar página',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in NotebookPaperSize.values)
                          ChoiceChip(
                            label: Text(item.label),
                            selected: size == item,
                            onSelected: (_) => setSheetState(() {
                              size = item;
                              if (item.isInfinite) landscape = false;
                            }),
                          ),
                      ],
                    ),
                    if (!size.isInfinite &&
                        size != NotebookPaperSize.square) ...[
                      const SizedBox(height: 10),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Retrato')),
                          ButtonSegment(value: true, label: Text('Paisagem')),
                        ],
                        selected: {landscape},
                        onSelectionChanged: (value) {
                          setSheetState(() => landscape = value.first);
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    DropdownButtonFormField<InkPageBackground>(
                      initialValue: background,
                      decoration: const InputDecoration(labelText: 'Modelo'),
                      items: [
                        for (final item in InkPageBackground.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(_backgroundLabel(item)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => background = value);
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Aplicar à página'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
    if (!apply) return;

    final paper = NotebookPaperPreset(size: size, landscape: landscape);
    await widget.inkStore.updatePageFormat(
      current.id,
      width: paper.width,
      height: paper.height,
      background: background,
    );
    await _load(selectPageId: current.id);
  }

  static String _backgroundLabel(InkPageBackground value) => switch (value) {
        InkPageBackground.blank => 'Em branco',
        InkPageBackground.ruled => 'Pautado',
        InkPageBackground.grid => 'Quadriculado',
        InkPageBackground.dotted => 'Pontilhado',
        InkPageBackground.cornell => 'Cornell',
        InkPageBackground.planner => 'Planner',
        InkPageBackground.taskList => 'Lista de tarefas',
        InkPageBackground.music => 'Partitura',
        InkPageBackground.isometric => 'Isométrico',
      };

  void _fitPage(Size viewport, InkNotebookPage page) {
    if (_fitPageId == page.id) return;
    _fitPageId = page.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page?.id != page.id) return;
      final infinite = NotebookPaperSize.infer(page.width, page.height).isInfinite;
      final scale = infinite
          ? 0.25
          : math.min(
              (viewport.width - 28) / page.width,
              (viewport.height - 28) / page.height,
            ).clamp(0.18, 1.0).toDouble();
      final dx = infinite ? 12.0 : math.max(12.0, (viewport.width - page.width * scale) / 2);
      final dy = infinite ? 12.0 : math.max(12.0, (viewport.height - page.height * scale) / 2);
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.notebook.title),
            if (page != null)
              Text(
                'Página ${page.pageNumber} de ${_pages.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Desfazer último traço',
            onPressed: _strokes.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Configurar página',
            onPressed: page == null ? null : _showPageSettings,
            icon: const Icon(Icons.tune),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'duplicate') unawaited(_duplicatePage());
              if (value == 'clear') unawaited(_clearPage());
              if (value == 'delete') unawaited(_deletePage());
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'duplicate',
                child: Text('Duplicar página'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Limpar página')),
              PopupMenuItem(
                value: 'delete',
                enabled: _pages.length > 1,
                child: const Text('Excluir página'),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: _ToolBar(
            tool: _tool,
            color: Color(_colorValue),
            selectionCount: _selectionCount,
            onSelect: _selectTool,
            onPenSettings: _showPenSettings,
          ),
        ),
      ),
      body: _loading || page == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewport = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      _fitPage(viewport, page);
                      final infinite =
                          NotebookPaperSize.infer(page.width, page.height)
                              .isInfinite;
                      return ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          minScale: 0.08,
                          maxScale: 6,
                          panEnabled: _hand,
                          scaleEnabled: true,
                          boundaryMargin: const EdgeInsets.all(1200),
                          child: Container(
                            width: page.width,
                            height: page.height,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: infinite
                                  ? null
                                  : Border.all(
                                      color: const Color(0xFFD0D4DA),
                                    ),
                              boxShadow: infinite
                                  ? null
                                  : const [
                                      BoxShadow(
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                        color: Color(0x28000000),
                                      ),
                                    ],
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                NotebookPageBackground(
                                  background: page.background,
                                ),
                                IgnorePointer(
                                  ignoring: _hand,
                                  child: InkCanvas(
                                    key: _canvasKey,
                                    initialStrokes: _strokes,
                                    pageId: page.id,
                                    tool: _inkTool,
                                    colorValue: _colorValue,
                                    strokeWidth: _width,
                                    stylusOnly: _stylusOnly,
                                    eraserMode: _eraser,
                                    lassoMode: _lasso,
                                    onStrokeCompleted: (stroke) {
                                      unawaited(widget.inkStore.addStroke(stroke));
                                      if (mounted) {
                                        setState(() {
                                          _strokes = [
                                            ..._strokes,
                                            stroke,
                                          ];
                                        });
                                      }
                                    },
                                    onStrokeUpdated: (stroke) {
                                      unawaited(widget.inkStore.addStroke(stroke));
                                    },
                                    onStrokeErased: (stroke) {
                                      unawaited(widget.inkStore.deleteStroke(stroke.id));
                                      if (mounted) {
                                        setState(() {
                                          _strokes = _strokes
                                              .where((item) => item.id != stroke.id)
                                              .toList(growable: false);
                                        });
                                      }
                                    },
                                    onSelectionChanged: (selection) {
                                      if (mounted) {
                                        setState(
                                          () => _selectionCount = selection.length,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _PageStrip(
                  pages: _pages,
                  selected: page,
                  onSelect: _openPage,
                  onAdd: _addPage,
                ),
              ],
            ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.color,
    required this.selectionCount,
    required this.onSelect,
    required this.onPenSettings,
  });

  final _NotebookTool tool;
  final Color color;
  final int selectionCount;
  final ValueChanged<_NotebookTool> onSelect;
  final VoidCallback onPenSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 58,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          children: [
            _tool(context, _NotebookTool.pen, Icons.edit, 'Caneta'),
            _tool(context, _NotebookTool.pencil, Icons.draw_outlined, 'Lápis'),
            _tool(
              context,
              _NotebookTool.highlighter,
              Icons.border_color_outlined,
              'Marca-texto',
            ),
            _tool(
              context,
              _NotebookTool.eraser,
              Icons.auto_fix_high_outlined,
              'Borracha',
            ),
            _tool(
              context,
              _NotebookTool.lasso,
              Icons.gesture,
              selectionCount > 0 ? 'Selecionados: $selectionCount' : 'Laço',
            ),
            _tool(context, _NotebookTool.hand, Icons.pan_tool_outlined, 'Mover'),
            const VerticalDivider(width: 18),
            IconButton(
              tooltip: 'Cor e espessura',
              onPressed: onPenSettings,
              icon: Icon(Icons.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tool(
    BuildContext context,
    _NotebookTool value,
    IconData icon,
    String tooltip,
  ) {
    final selected = tool == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        isSelected: selected,
        onPressed: () => onSelect(value),
        icon: Icon(icon),
      ),
    );
  }
}

class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.pages,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final List<InkNotebookPage> pages;
  final InkNotebookPage selected;
  final ValueChanged<InkNotebookPage> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [
              for (final page in pages)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    selected: page.id == selected.id,
                    onSelected: (_) => onSelect(page),
                    avatar: const Icon(Icons.description_outlined, size: 17),
                    label: Text('${page.pageNumber}'),
                  ),
                ),
              IconButton(
                tooltip: 'Adicionar página',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

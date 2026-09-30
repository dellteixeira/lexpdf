import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_paper.dart';
import '../core/notebook/notebook_pdf_exporter.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_page_background.dart';

enum _NotebookTool { pen, highlighter, eraser, lasso, hand }

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
  int _penColorValue = 0xFF1E1E1E;
  double _penWidth = 3.2;
  double _penOpacity = 1.0;
  InkBrush _penBrush = InkBrush.round;
  int _highlighterColorValue = 0xFFFFC107;
  double _highlighterWidth = 14;
  double _highlighterOpacity = 0.28;
  InkBrush _highlighterBrush = InkBrush.chisel;
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

  InkTool get _inkTool =>
      _tool == _NotebookTool.highlighter ? InkTool.highlighter : InkTool.pen;

  int get _activeColorValue => _tool == _NotebookTool.highlighter
      ? _highlighterColorValue
      : _penColorValue;

  double get _activeWidth =>
      _tool == _NotebookTool.highlighter ? _highlighterWidth : _penWidth;

  double get _activeOpacity =>
      _tool == _NotebookTool.highlighter ? _highlighterOpacity : _penOpacity;

  InkBrush get _activeBrush =>
      _tool == _NotebookTool.highlighter ? _highlighterBrush : _penBrush;

  bool get _eraser => _tool == _NotebookTool.eraser;
  bool get _lasso => _tool == _NotebookTool.lasso;
  bool get _hand => _tool == _NotebookTool.hand;

  void _selectTool(_NotebookTool tool) {
    setState(() {
      _tool = tool;
      if (tool != _NotebookTool.lasso) _selectionCount = 0;
    });
  }

  Future<void> _deleteSelection() async {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    final removed = canvas.deleteSelected();
    if (removed.isEmpty) return;
    for (final stroke in removed) {
      await widget.inkStore.deleteStroke(stroke.id);
    }
    if (!mounted) return;
    setState(() {
      _strokes = canvas.strokes;
      _selectionCount = 0;
    });
  }

  void _rememberUpdatedStroke(InkStroke stroke) {
    final index = _strokes.indexWhere((item) => item.id == stroke.id);
    if (index < 0) {
      _strokes = List<InkStroke>.unmodifiable([..._strokes, stroke]);
      return;
    }
    final updated = [..._strokes];
    updated[index] = stroke;
    _strokes = List<InkStroke>.unmodifiable(updated);
  }

  Future<void> _exportPdf() async {
    if (_pages.isEmpty) return;
    final safeName = widget.notebook.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final location = await getSaveLocation(
      suggestedName: '${safeName.isEmpty ? 'caderno' : safeName}.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
      confirmButtonText: 'Exportar',
    );
    if (location == null) return;

    final data = <NotebookExportPageData>[];
    for (final page in _pages) {
      data.add(
        NotebookExportPageData(
          page: page,
          strokes: await widget.inkStore.listStrokes(page.id),
          objects: const [],
        ),
      );
    }
    final bytes = await const NotebookPdfExporter().export(
      title: widget.notebook.title,
      pages: data,
    );
    await File(location.path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caderno exportado para PDF.')),
    );
  }

  Future<void> _organizePages() async {
    final ordered = [..._pages];
    final changed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Organizar páginas',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Concluir'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: ordered.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setSheetState(() {
                            final item = ordered.removeAt(oldIndex);
                            ordered.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final page = ordered[index];
                          return ListTile(
                            key: ValueKey(page.id),
                            leading: CircleAvatar(
                              child: Text('${index + 1}'),
                            ),
                            title: Text(
                              'Página ${page.pageNumber} · ${_backgroundLabel(page.background)}',
                            ),
                            subtitle: Text(
                              NotebookPaperSize.infer(page.width, page.height).label,
                            ),
                            trailing: const Icon(Icons.drag_handle),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
    if (!changed) return;
    await widget.inkStore.reorderPages(
      widget.notebook.id,
      ordered.map((page) => page.id).toList(growable: false),
    );
    await _load(selectPageId: _page?.id);
  }

  Future<void> _showInkSettings() async {
    if (_tool != _NotebookTool.pen && _tool != _NotebookTool.highlighter) {
      return;
    }
    final editingHighlighter = _tool == _NotebookTool.highlighter;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          const penColors = <int>[
            0xFF000000,
            0xFF424242,
            0xFF757575,
            0xFF1A237E,
            0xFF246BFD,
            0xFF039BE5,
            0xFF00ACC1,
            0xFF00897B,
            0xFF188038,
            0xFF7CB342,
            0xFFF9A825,
            0xFFFF8F00,
            0xFFF4511E,
            0xFFD93025,
            0xFFD81B60,
            0xFF7B1FA2,
            0xFF5D4037,
          ];
          const highlighterColors = <int>[
            0xFFFFEB3B,
            0xFFFFC107,
            0xFFFF9800,
            0xFFFF7043,
            0xFFFF8A80,
            0xFFF48FB1,
            0xFFCE93D8,
            0xFF90CAF9,
            0xFF4DD0E1,
            0xFF80CBC4,
            0xFFA5D6A7,
            0xFFC5E1A5,
          ];
          final colors = editingHighlighter ? highlighterColors : penColors;
          final selectedColor =
              editingHighlighter ? _highlighterColorValue : _penColorValue;
          final width = editingHighlighter ? _highlighterWidth : _penWidth;
          final opacity =
              editingHighlighter ? _highlighterOpacity : _penOpacity;
          final brush =
              editingHighlighter ? _highlighterBrush : _penBrush;
          final sizePresets = editingHighlighter
              ? const <double>[6, 10, 14, 20, 28, 36]
              : const <double>[1, 2, 3.2, 5, 8, 12, 18];
          final title = editingHighlighter ? 'Marca-texto' : 'Caneta';

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  Text(
                    'Tipo de brush',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in InkBrush.values)
                        ChoiceChip(
                          label: Text(_brushLabel(item)),
                          selected: brush == item,
                          onSelected: (_) {
                            setState(() {
                              if (editingHighlighter) {
                                _highlighterBrush = item;
                              } else {
                                _penBrush = item;
                              }
                            });
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Cor', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in colors)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (editingHighlighter) {
                                _highlighterColorValue = color;
                              } else {
                                _penColorValue = color;
                              }
                            });
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
                                color: selectedColor == color
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
                  Text(
                    'Tamanho do brush: ${width.toStringAsFixed(1)} px',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in sizePresets)
                        ChoiceChip(
                          label: Text(
                            preset == preset.roundToDouble()
                                ? preset.toInt().toString()
                                : preset.toStringAsFixed(1),
                          ),
                          selected: (width - preset).abs() < 0.05,
                          onSelected: (_) {
                            setState(() {
                              if (editingHighlighter) {
                                _highlighterWidth = preset;
                              } else {
                                _penWidth = preset;
                              }
                            });
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  Slider(
                    value: width,
                    min: editingHighlighter ? 4 : 1,
                    max: editingHighlighter ? 40 : 18,
                    divisions: editingHighlighter ? 36 : 34,
                    onChanged: (value) {
                      setState(() {
                        if (editingHighlighter) {
                          _highlighterWidth = value;
                        } else {
                          _penWidth = value;
                        }
                      });
                      setSheetState(() {});
                    },
                  ),
                  Text('Opacidade: ${(opacity * 100).round()}%'),
                  Slider(
                    value: opacity,
                    min: 0.1,
                    max: 1,
                    divisions: 18,
                    onChanged: (value) {
                      setState(() {
                        if (editingHighlighter) {
                          _highlighterOpacity = value;
                        } else {
                          _penOpacity = value;
                        }
                      });
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

  static String _brushLabel(InkBrush brush) => switch (brush) {
        InkBrush.round => 'Redondo',
        InkBrush.fountain => 'Tinteiro',
        InkBrush.chisel => 'Chanfrado',
      };

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
            Text(
              widget.notebook.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (page != null)
              Text(
                'Página ${page.pageNumber} de ${_pages.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
              if (value == 'export') unawaited(_exportPdf());
              if (value == 'organize') unawaited(_organizePages());
              if (value == 'duplicate') unawaited(_duplicatePage());
              if (value == 'clear') unawaited(_clearPage());
              if (value == 'delete') unawaited(_deletePage());
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Exportar caderno para PDF'),
              ),
              const PopupMenuItem(
                value: 'organize',
                child: Text('Organizar páginas'),
              ),
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
            color: Color(_activeColorValue),
            selectionCount: _selectionCount,
            onSelect: _selectTool,
            onInkSettings: _showInkSettings,
            onDeleteSelection: _deleteSelection,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                              boxShadow: infinite
                                  ? null
                                  : const [
                                      BoxShadow(
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                        color: Color(0x18000000),
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
                                    colorValue: _activeColorValue,
                                    strokeWidth: _activeWidth,
                                    brush: _activeBrush,
                                    strokeOpacity: _activeOpacity,
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
                                      _rememberUpdatedStroke(stroke);
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
    required this.onInkSettings,
    required this.onDeleteSelection,
  });

  final _NotebookTool tool;
  final Color color;
  final int selectionCount;
  final ValueChanged<_NotebookTool> onSelect;
  final VoidCallback onInkSettings;
  final VoidCallback onDeleteSelection;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SizedBox(
        height: 58,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          children: [
            _tool(context, _NotebookTool.pen, Icons.edit, 'Caneta'),
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
            if (selectionCount > 0) ...[
              const VerticalDivider(width: 18),
              Tooltip(
                message:
                    'Arraste a seleção para mover. Use a alça no canto para redimensionar.',
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.open_with),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Excluir seleção',
                onPressed: onDeleteSelection,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
            const VerticalDivider(width: 18),
            IconButton.filledTonal(
              tooltip: tool == _NotebookTool.highlighter
                  ? 'Configurar marca-texto: brush, cor, tamanho e opacidade'
                  : 'Configurar caneta: brush, cor, tamanho e opacidade',
              onPressed: tool == _NotebookTool.pen ||
                      tool == _NotebookTool.highlighter
                  ? onInkSettings
                  : null,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
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

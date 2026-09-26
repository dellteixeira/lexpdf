import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/ink_canvas.dart';
import '../widgets/notebook_page_background.dart';

class StylusNotebookEditorScreen extends StatefulWidget {
  const StylusNotebookEditorScreen({
    required this.inkStore,
    required this.notebook,
    this.initialPageId,
    super.key,
  });

  final LocalInkStore inkStore;
  final InkNotebook notebook;
  final String? initialPageId;

  @override
  State<StylusNotebookEditorScreen> createState() =>
      _StylusNotebookEditorScreenState();
}

class _StylusNotebookEditorScreenState
    extends State<StylusNotebookEditorScreen> {
  static const _palette = <int>[
    0xFF111827,
    0xFF1D4ED8,
    0xFFDC2626,
    0xFF15803D,
    0xFF7E22CE,
    0xFFEA580C,
    0xFFF59E0B,
    0xFF0891B2,
  ];

  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  final TransformationController _transform = TransformationController();

  List<InkNotebookPage> _pages = const [];
  List<InkStroke> _strokes = const [];
  final List<InkStroke> _redo = <InkStroke>[];

  InkNotebookPage? _page;
  InkTool _tool = InkTool.pen;
  int _colorValue = _palette.first;
  double _strokeWidth = 3.0;
  bool _stylusOnly = true;
  bool _eraserMode = false;
  bool _lassoMode = false;
  int _selectionCount = 0;
  bool _loading = true;
  Size? _lastViewportSize;
  String? _lastFittedPageId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNotebook());
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  int get _pageIndex {
    final page = _page;
    if (page == null) return -1;
    return _pages.indexWhere((item) => item.id == page.id);
  }

  Future<void> _loadNotebook({String? preferredPageId}) async {
    if (mounted) setState(() => _loading = true);
    var pages = await widget.inkStore.listPages(widget.notebook.id);
    if (pages.isEmpty) {
      await widget.inkStore.createPage(widget.notebook.id);
      pages = await widget.inkStore.listPages(widget.notebook.id);
    }
    final requested = preferredPageId ?? widget.initialPageId;
    final target = requested == null
        ? pages.first
        : pages.firstWhere(
            (item) => item.id == requested,
            orElse: () => pages.first,
          );
    final strokes = await widget.inkStore.listStrokes(target.id);

    if (!mounted) return;
    setState(() {
      _pages = pages;
      _page = target;
      _strokes = strokes;
      _redo.clear();
      _selectionCount = 0;
      _loading = false;
      _lastFittedPageId = null;
    });
  }

  Future<void> _switchPage(InkNotebookPage page) async {
    if (_page?.id == page.id || _loading) return;
    final strokes = await widget.inkStore.listStrokes(page.id);
    if (!mounted) return;
    setState(() {
      _page = page;
      _strokes = strokes;
      _redo.clear();
      _selectionCount = 0;
      _eraserMode = false;
      _lassoMode = false;
      _lastFittedPageId = null;
    });
  }

  Future<void> _addPage() async {
    final current = _page;
    final created = await widget.inkStore.createPage(
      widget.notebook.id,
      background: current?.background ?? InkPageBackground.blank,
      format: current?.format == InkPageFormat.custom
          ? InkPageFormat.a4Portrait
          : current?.format ?? InkPageFormat.a4Portrait,
    );
    await _loadNotebook(preferredPageId: created.id);
  }

  Future<void> _duplicatePage() async {
    final current = _page;
    if (current == null) return;
    final duplicate = await widget.inkStore.duplicatePage(current);
    await _loadNotebook(preferredPageId: duplicate.id);
  }

  Future<void> _deletePage() async {
    final current = _page;
    if (current == null) return;
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O caderno precisa ter ao menos uma página.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir página?'),
            content: Text(
              'A página ${current.pageNumber} e todos os seus traços serão removidos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final index = _pageIndex;
    await widget.inkStore.deletePage(current.id);
    final remaining = await widget.inkStore.listPages(widget.notebook.id);
    final nextIndex = math.min(index, remaining.length - 1);
    await _loadNotebook(preferredPageId: remaining[nextIndex].id);
  }

  Future<void> _onStrokeCompleted(InkStroke stroke) async {
    _redo.clear();
    await widget.inkStore.addStroke(stroke);
    if (!mounted) return;
    setState(() {
      _strokes = [..._strokes.where((item) => item.id != stroke.id), stroke];
    });
  }

  Future<void> _onStrokeUpdated(InkStroke stroke) async {
    await widget.inkStore.addStroke(stroke);
    if (!mounted) return;
    setState(() {
      _strokes = _strokes
          .map((item) => item.id == stroke.id ? stroke : item)
          .toList(growable: false);
    });
  }

  Future<void> _onStrokeErased(InkStroke stroke) async {
    _redo.clear();
    await widget.inkStore.deleteStroke(stroke.id);
    if (!mounted) return;
    setState(() {
      _strokes = _strokes.where((item) => item.id != stroke.id).toList();
    });
  }

  Future<void> _undo() async {
    final removed = _canvasKey.currentState?.undoLast();
    if (removed == null) return;
    await widget.inkStore.deleteStroke(removed.id);
    if (!mounted) return;
    setState(() {
      _redo.add(removed);
      _strokes = _strokes.where((item) => item.id != removed.id).toList();
      _selectionCount = 0;
    });
  }

  Future<void> _redoStroke() async {
    if (_redo.isEmpty) return;
    final stroke = _redo.removeLast();
    await widget.inkStore.addStroke(stroke);
    _canvasKey.currentState?.restoreStroke(stroke);
    if (!mounted) return;
    setState(() {
      _strokes = [..._strokes.where((item) => item.id != stroke.id), stroke];
    });
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
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Limpar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.inkStore.clearPage(current.id);
    _canvasKey.currentState?.clear();
    if (!mounted) return;
    setState(() {
      _strokes = const [];
      _redo.clear();
      _selectionCount = 0;
    });
  }

  void _activateTool(InkTool tool) {
    setState(() {
      _tool = tool;
      _eraserMode = false;
      _lassoMode = false;
    });
  }

  void _activateEraser() {
    setState(() {
      _eraserMode = true;
      _lassoMode = false;
    });
  }

  void _activateLasso() {
    setState(() {
      _lassoMode = true;
      _eraserMode = false;
    });
  }

  Future<void> _deleteSelection() async {
    final removed = _canvasKey.currentState?.deleteSelected() ?? const [];
    for (final stroke in removed) {
      await widget.inkStore.deleteStroke(stroke.id);
    }
    if (!mounted) return;
    setState(() {
      final ids = removed.map((item) => item.id).toSet();
      _strokes = _strokes.where((item) => !ids.contains(item.id)).toList();
      _selectionCount = 0;
      _redo.clear();
    });
  }

  Future<void> _copySelection() async {
    _canvasKey.currentState?.copySelected();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seleção copiada.')),
    );
  }

  Future<void> _pasteSelection() async {
    final inserted = _canvasKey.currentState?.pasteClipboard() ?? const [];
    for (final stroke in inserted) {
      await widget.inkStore.addStroke(stroke);
    }
    if (!mounted) return;
    setState(() {
      _strokes = [..._strokes, ...inserted];
      _selectionCount = inserted.length;
      _redo.clear();
    });
  }

  Future<void> _showPageSettings() async {
    final current = _page;
    if (current == null) return;
    final result = await showModalBottomSheet<
        ({InkPageFormat format, InkPageBackground background})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PageSettingsSheet(
        format: current.format,
        background: current.background,
      ),
    );
    if (result == null) return;

    if (result.format != current.format) {
      await widget.inkStore.updatePageFormat(current.id, result.format);
    }
    if (result.background != current.background) {
      await widget.inkStore.updatePageBackground(current.id, result.background);
    }
    await _loadNotebook(preferredPageId: current.id);
  }

  void _fitPage(Size viewport) {
    final page = _page;
    if (page == null || viewport.isEmpty) return;
    final availableWidth = math.max(100.0, viewport.width - 32);
    final availableHeight = math.max(100.0, viewport.height - 32);
    final scale = math.min(
      1.0,
      math.min(availableWidth / page.width, availableHeight / page.height),
    ).clamp(0.12, 1.0).toDouble();
    final tx = (viewport.width - page.width * scale) / 2;
    final ty = (viewport.height - page.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    _lastViewportSize = viewport;
    _lastFittedPageId = page.id;
  }

  void _scheduleFit(Size viewport) {
    final page = _page;
    if (page == null) return;
    if (_lastFittedPageId == page.id && _lastViewportSize == viewport) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitPage(viewport);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final scheme = Theme.of(context).colorScheme;

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
                'Página ${page.pageNumber} de ${_pages.length} • ${page.format.label}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Desfazer',
            onPressed: _strokes.isEmpty ? null : () => unawaited(_undo()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Refazer',
            onPressed: _redo.isEmpty ? null : () => unawaited(_redoStroke()),
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Ajustar página',
            onPressed: page == null ? null : _showPageSettings,
            icon: const Icon(Icons.tune),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (value) {
              switch (value) {
                case 'duplicate':
                  unawaited(_duplicatePage());
                  break;
                case 'clear':
                  unawaited(_clearPage());
                  break;
                case 'delete':
                  unawaited(_deletePage());
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  leading: Icon(Icons.copy_outlined),
                  title: Text('Duplicar página'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.layers_clear_outlined),
                  title: Text('Limpar página'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Excluir página'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading || page == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildToolBar(),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewport = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      _scheduleFit(viewport);
                      return ColoredBox(
                        color: scheme.surfaceContainerLow,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          panEnabled: false,
                          scaleEnabled: false,
                          minScale: 0.12,
                          maxScale: 6,
                          boundaryMargin: EdgeInsets.all(
                            page.format == InkPageFormat.infinite ? 4200 : 500,
                          ),
                          child: RepaintBoundary(
                            child: Container(
                              width: page.width,
                              height: page.height,
                              decoration: BoxDecoration(
                                boxShadow: page.format == InkPageFormat.infinite
                                    ? const []
                                    : const [
                                        BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 18,
                                          offset: Offset(0, 7),
                                        ),
                                      ],
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  NotebookPageBackground(
                                    background: page.background,
                                  ),
                                  InkCanvas(
                                    key: _canvasKey,
                                    initialStrokes: _strokes,
                                    pageId: page.id,
                                    tool: _tool,
                                    colorValue: _colorValue,
                                    strokeWidth: _strokeWidth,
                                    stylusOnly: _stylusOnly,
                                    eraserMode: _eraserMode,
                                    lassoMode: _lassoMode,
                                    onStrokeCompleted: (stroke) =>
                                        unawaited(_onStrokeCompleted(stroke)),
                                    onStrokeUpdated: (stroke) =>
                                        unawaited(_onStrokeUpdated(stroke)),
                                    onStrokeErased: (stroke) =>
                                        unawaited(_onStrokeErased(stroke)),
                                    onSelectionChanged: (ids) {
                                      if (mounted) {
                                        setState(
                                          () => _selectionCount = ids.length,
                                        );
                                      }
                                    },
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
                _buildPageStrip(),
              ],
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPage,
              icon: const Icon(Icons.add),
              label: const Text('Página'),
            ),
    );
  }

  Widget _buildToolBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 72,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          scrollDirection: Axis.horizontal,
          children: [
            _ToolButton(
              icon: Icons.edit,
              label: 'Caneta',
              selected: !_eraserMode && !_lassoMode && _tool == InkTool.pen,
              onTap: () => _activateTool(InkTool.pen),
            ),
            _ToolButton(
              icon: Icons.draw_outlined,
              label: 'Lápis',
              selected: !_eraserMode && !_lassoMode && _tool == InkTool.pencil,
              onTap: () => _activateTool(InkTool.pencil),
            ),
            _ToolButton(
              icon: Icons.format_color_fill_outlined,
              label: 'Marca',
              selected:
                  !_eraserMode && !_lassoMode && _tool == InkTool.highlighter,
              onTap: () => _activateTool(InkTool.highlighter),
            ),
            _ToolButton(
              icon: Icons.auto_fix_off_outlined,
              label: 'Borracha',
              selected: _eraserMode,
              onTap: _activateEraser,
            ),
            _ToolButton(
              icon: Icons.gesture,
              label: 'Laço',
              selected: _lassoMode,
              onTap: _activateLasso,
            ),
            const VerticalDivider(width: 18),
            for (final value in _palette)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () => setState(() => _colorValue = value),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(value),
                      border: Border.all(
                        color: _colorValue == value
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: _colorValue == value ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            SizedBox(
              width: 142,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 18),
                  Expanded(
                    child: Slider(
                      value: _strokeWidth,
                      min: 1,
                      max: 14,
                      onChanged: (value) =>
                          setState(() => _strokeWidth = value),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 18),
            FilterChip(
              selected: _stylusOnly,
              avatar: const Icon(Icons.edit_outlined, size: 17),
              label: Text(_stylusOnly ? 'Somente caneta' : 'Caneta + toque'),
              onSelected: (value) => setState(() => _stylusOnly = value),
            ),
            if (_selectionCount > 0) ...[
              const SizedBox(width: 10),
              ActionChip(
                avatar: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Copiar'),
                onPressed: _copySelection,
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.delete_outline, size: 17),
                label: Text('Excluir ($_selectionCount)'),
                onPressed: _deleteSelection,
              ),
            ],
            if (_canvasKey.currentState?.hasClipboard ?? false) ...[
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.content_paste, size: 17),
                label: const Text('Colar'),
                onPressed: _pasteSelection,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPageStrip() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 110, 8),
            itemCount: _pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = _pages[index];
              final selected = item.id == _page?.id;
              return InkWell(
                onTap: () => _switchPage(item),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${item.pageNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageSettingsSheet extends StatefulWidget {
  const _PageSettingsSheet({
    required this.format,
    required this.background,
  });

  final InkPageFormat format;
  final InkPageBackground background;

  @override
  State<_PageSettingsSheet> createState() => _PageSettingsSheetState();
}

class _PageSettingsSheetState extends State<_PageSettingsSheet> {
  late InkPageFormat _format = widget.format == InkPageFormat.custom
      ? InkPageFormat.a4Portrait
      : widget.format;
  late InkPageBackground _background = widget.background;

  @override
  Widget build(BuildContext context) {
    final formats = <InkPageFormat>[
      InkPageFormat.a4Portrait,
      InkPageFormat.a4Landscape,
      InkPageFormat.a3Portrait,
      InkPageFormat.a3Landscape,
      InkPageFormat.infinite,
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configurações da página',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              Text('Tamanho', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in formats)
                    ChoiceChip(
                      selected: _format == format,
                      label: Text(format.label),
                      onSelected: (_) => setState(() => _format = format),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text('Papel', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: InkPageBackground.values.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  childAspectRatio: 1.15,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final background = InkPageBackground.values[index];
                  final selected = background == _background;
                  return InkWell(
                    onTap: () => setState(() => _background = background),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NotebookPageBackground(
                              background: background,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                child: Text(
                                  background.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF202124),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    (format: _format, background: _background),
                  ),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

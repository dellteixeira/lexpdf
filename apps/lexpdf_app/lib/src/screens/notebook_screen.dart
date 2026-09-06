import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_ink_store.dart';
import '../widgets/ink_canvas.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({required this.inkStore, super.key});

  final LocalInkStore inkStore;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookSession {
  const _NotebookSession(this.page, this.strokes);
  final InkNotebookPage page;
  final List<InkStroke> strokes;
}

class _NotebookScreenState extends State<NotebookScreen> {
  static const double _moveStep = 12;
  static const double _scaleDown = 0.9;
  static const double _scaleUp = 1.1;
  static const double _rotationStep = math.pi / 12;

  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  late final Future<_NotebookSession> _session = _loadSession();

  InkTool _tool = InkTool.pen;
  int _colorValue = 0xFF1C1B1F;
  double _width = 3.0;
  bool _stylusOnly = true;
  bool _eraserMode = false;
  bool _lassoMode = false;
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

  Future<_NotebookSession> _loadSession() async {
    final page = await widget.inkStore.ensureDefaultPage();
    final strokes = await widget.inkStore.listStrokes(page.id);
    return _NotebookSession(page, strokes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu caderno'),
        actions: [
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
          IconButton(
            tooltip: 'Limpar página',
            onPressed: _clearPage,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<_NotebookSession>(
        future: _session,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Não foi possível abrir o caderno: ${snapshot.error}'),
            );
          }
          final session = snapshot.requireData;
          return Column(
            children: [
              _buildToolbar(),
              const Divider(height: 1),
              Expanded(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: session.page.width / session.page.height,
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
                        child: InkCanvas(
                          key: _canvasKey,
                          initialStrokes: session.strokes,
                          pageId: session.page.id,
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
                ButtonSegment(
                  value: InkTool.pen,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Caneta'),
                ),
                ButtonSegment(
                  value: InkTool.pencil,
                  icon: Icon(Icons.draw_outlined),
                  label: Text('Lápis'),
                ),
                ButtonSegment(
                  value: InkTool.highlighter,
                  icon: Icon(Icons.border_color_outlined),
                  label: Text('Marca-texto'),
                ),
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
              label: Text(
                _selectionCount > 0 ? 'Laço ($_selectionCount)' : 'Laço',
              ),
              onSelected: (value) => setState(() {
                _lassoMode = value;
                _eraserMode = false;
                if (!value) _selectionCount = 0;
              }),
            ),
            if (_lassoMode && _selectionCount > 0) ...[
              const SizedBox(width: 8),
              const Text('Mover'),
              IconButton(
                tooltip: 'Mover seleção para a esquerda',
                onPressed: () => _moveSelection(-_moveStep, 0),
                icon: const Icon(Icons.arrow_left),
              ),
              IconButton(
                tooltip: 'Mover seleção para cima',
                onPressed: () => _moveSelection(0, -_moveStep),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Mover seleção para baixo',
                onPressed: () => _moveSelection(0, _moveStep),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Mover seleção para a direita',
                onPressed: () => _moveSelection(_moveStep, 0),
                icon: const Icon(Icons.arrow_right),
              ),
              const SizedBox(width: 8),
              const Text('Tamanho'),
              IconButton(
                tooltip: 'Diminuir seleção',
                onPressed: () => _scaleSelection(_scaleDown),
                icon: const Icon(Icons.zoom_in_map),
              ),
              IconButton(
                tooltip: 'Aumentar seleção',
                onPressed: () => _scaleSelection(_scaleUp),
                icon: const Icon(Icons.zoom_out_map),
              ),
              const SizedBox(width: 8),
              const Text('Girar'),
              IconButton(
                tooltip: 'Girar seleção 15° à esquerda',
                onPressed: () => _rotateSelection(-_rotationStep),
                icon: const Icon(Icons.rotate_left),
              ),
              IconButton(
                tooltip: 'Girar seleção 15° à direita',
                onPressed: () => _rotateSelection(_rotationStep),
                icon: const Icon(Icons.rotate_right),
              ),
            ],
            const SizedBox(width: 16),
            for (final value in _palette)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _eraserMode || _lassoMode
                      ? null
                      : () => setState(() => _colorValue = value),
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
                onChanged: _eraserMode || _lassoMode
                    ? null
                    : (value) => setState(() => _width = value),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _stylusOnly,
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Somente caneta'),
              onSelected: (value) => setState(() => _stylusOnly = value),
            ),
          ],
        ),
      ),
    );
  }

  void _moveSelection(double dx, double dy) {
    _canvasKey.currentState?.moveSelected(dx, dy);
  }

  void _scaleSelection(double factor) {
    _canvasKey.currentState?.scaleSelected(factor);
  }

  void _rotateSelection(double angleRadians) {
    _canvasKey.currentState?.rotateSelected(angleRadians);
  }

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
    final state = _canvasKey.currentState;
    if (state == null) return;
    await widget.inkStore.clearPage(
      state.strokes.firstOrNull?.pageId ?? 'default-page-1',
    );
    state.clear();
    if (mounted) setState(() => _selectionCount = 0);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

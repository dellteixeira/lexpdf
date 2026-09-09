import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';

class NotebookInkControls extends StatelessWidget {
  const NotebookInkControls({
    required this.editable,
    required this.pointerMode,
    required this.handMode,
    required this.tool,
    required this.eraserMode,
    required this.lassoMode,
    required this.selectionCount,
    required this.onPointerModeChanged,
    required this.onHandModeChanged,
    required this.onToolChanged,
    required this.onEraserModeChanged,
    required this.onLassoModeChanged,
    super.key,
  });

  final bool editable;
  final bool pointerMode;
  final bool handMode;
  final InkTool tool;
  final bool eraserMode;
  final bool lassoMode;
  final int selectionCount;

  final ValueChanged<bool> onPointerModeChanged;
  final ValueChanged<bool> onHandModeChanged;
  final ValueChanged<InkTool> onToolChanged;
  final ValueChanged<bool> onEraserModeChanged;
  final ValueChanged<bool> onLassoModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          selected: pointerMode,
          avatar: const Icon(Icons.near_me_outlined, size: 18),
          label: const Text('Selecionar'),
          onSelected: editable ? onPointerModeChanged : null,
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: handMode,
          avatar: const Icon(Icons.pan_tool_alt_outlined, size: 18),
          label: const Text('Mão'),
          onSelected: onHandModeChanged,
        ),
        const SizedBox(width: 6),
        SegmentedButton<InkTool>(
          showSelectedIcon: false,
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
          selected: {tool},
          onSelectionChanged: editable
              ? (selection) => onToolChanged(selection.first)
              : null,
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: eraserMode,
          avatar: const Icon(Icons.auto_fix_normal_outlined, size: 18),
          label: const Text('Borracha'),
          onSelected: editable ? onEraserModeChanged : null,
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: lassoMode,
          avatar: const Icon(Icons.gesture, size: 18),
          label: Text(selectionCount > 0 ? 'Laço ($selectionCount)' : 'Laço'),
          onSelected: editable ? onLassoModeChanged : null,
        ),
      ],
    );
  }
}

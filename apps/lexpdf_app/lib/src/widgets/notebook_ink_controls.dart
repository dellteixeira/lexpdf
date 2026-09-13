import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import 'notebook_wordpad_chrome.dart';

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
        WordPadLabeledCommand(
          label: 'Selecionar',
          icon: Icons.near_me_outlined,
          selected: pointerMode,
          onPressed: editable ? () => onPointerModeChanged(!pointerMode) : null,
        ),
        WordPadLabeledCommand(
          label: 'Mão',
          icon: Icons.pan_tool_alt_outlined,
          selected: handMode,
          onPressed: () => onHandModeChanged(!handMode),
        ),
        WordPadLabeledCommand(
          label: 'Caneta',
          icon: Icons.edit_outlined,
          selected: !eraserMode && !lassoMode && tool == InkTool.pen,
          onPressed: editable ? () => onToolChanged(InkTool.pen) : null,
        ),
        WordPadLabeledCommand(
          label: 'Lápis',
          icon: Icons.draw_outlined,
          selected: !eraserMode && !lassoMode && tool == InkTool.pencil,
          onPressed: editable ? () => onToolChanged(InkTool.pencil) : null,
        ),
        WordPadLabeledCommand(
          label: 'Marca-texto',
          icon: Icons.border_color_outlined,
          selected: !eraserMode && !lassoMode && tool == InkTool.highlighter,
          onPressed: editable ? () => onToolChanged(InkTool.highlighter) : null,
        ),
        WordPadLabeledCommand(
          label: 'Borracha',
          icon: Icons.auto_fix_normal_outlined,
          selected: eraserMode,
          onPressed: editable ? () => onEraserModeChanged(!eraserMode) : null,
        ),
        WordPadLabeledCommand(
          label: selectionCount > 0 ? 'Laço $selectionCount' : 'Laço',
          icon: Icons.gesture,
          selected: lassoMode,
          onPressed: editable ? () => onLassoModeChanged(!lassoMode) : null,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

class NotebookLassoTools extends StatelessWidget {
  const NotebookLassoTools({
    required this.editable,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onScaleDown,
    required this.onScaleUp,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onDecreaseWidth,
    required this.onIncreaseWidth,
    required this.onCopy,
    required this.onDuplicate,
    required this.onCut,
    required this.onRecognize,
    super.key,
  });

  final bool editable;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onScaleDown;
  final VoidCallback onScaleUp;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onDecreaseWidth;
  final VoidCallback onIncreaseWidth;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final VoidCallback onCut;
  final VoidCallback onRecognize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: editable ? onMoveLeft : null,
          icon: const Icon(Icons.arrow_left),
        ),
        IconButton(
          onPressed: editable ? onMoveRight : null,
          icon: const Icon(Icons.arrow_right),
        ),
        IconButton(
          onPressed: editable ? onScaleDown : null,
          icon: const Icon(Icons.zoom_in_map),
        ),
        IconButton(
          onPressed: editable ? onScaleUp : null,
          icon: const Icon(Icons.zoom_out_map),
        ),
        IconButton(
          onPressed: editable ? onRotateLeft : null,
          icon: const Icon(Icons.rotate_left),
        ),
        IconButton(
          onPressed: editable ? onRotateRight : null,
          icon: const Icon(Icons.rotate_right),
        ),
        IconButton(
          onPressed: editable ? onDecreaseWidth : null,
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          onPressed: editable ? onIncreaseWidth : null,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: 'Copiar',
          onPressed: onCopy,
          icon: const Icon(Icons.content_copy),
        ),
        IconButton(
          tooltip: 'Duplicar',
          onPressed: editable ? onDuplicate : null,
          icon: const Icon(Icons.copy_all_outlined),
        ),
        IconButton(
          tooltip: 'Recortar',
          onPressed: editable ? onCut : null,
          icon: const Icon(Icons.content_cut),
        ),
        IconButton(
          tooltip: 'Reconhecer forma',
          onPressed: editable ? onRecognize : null,
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
      ],
    );
  }
}

class NotebookStyleControls extends StatelessWidget {
  const NotebookStyleControls({
    required this.editable,
    required this.pointerMode,
    required this.objectSelected,
    required this.eraserMode,
    required this.lassoMode,
    required this.selectionCount,
    required this.rulerMode,
    required this.palette,
    required this.colorValue,
    required this.width,
    required this.stylusOnly,
    required this.onRulerModeChanged,
    required this.onColorSelected,
    required this.onWidthChanged,
    required this.onStylusOnlyChanged,
    required this.onClearActiveLayer,
    super.key,
  });

  final bool editable;
  final bool pointerMode;
  final bool objectSelected;
  final bool eraserMode;
  final bool lassoMode;
  final int selectionCount;
  final bool rulerMode;
  final List<int> palette;
  final int colorValue;
  final double width;
  final bool stylusOnly;
  final ValueChanged<bool> onRulerModeChanged;
  final ValueChanged<int> onColorSelected;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<bool> onStylusOnlyChanged;
  final VoidCallback onClearActiveLayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canStyle = editable &&
        !eraserMode &&
        (!lassoMode || selectionCount > 0) &&
        (!pointerMode || objectSelected);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          selected: rulerMode,
          avatar: const Icon(Icons.straighten, size: 18),
          label: const Text('Régua'),
          onSelected: onRulerModeChanged,
        ),
        const SizedBox(width: 8),
        for (final value in palette)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: canStyle ? () => onColorSelected(value) : null,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Color(value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorValue == value
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: colorValue == value ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(objectSelected ? 'Espessura do objeto' : 'Espessura'),
        SizedBox(
          width: 120,
          child: Slider(
            min: 1,
            max: 10,
            value: width.clamp(1.0, 10.0).toDouble(),
            onChanged: canStyle && !lassoMode ? onWidthChanged : null,
          ),
        ),
        FilterChip(
          selected: stylusOnly,
          avatar: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Somente caneta'),
          onSelected: editable ? onStylusOnlyChanged : null,
        ),
        IconButton(
          tooltip: 'Limpar camada ativa',
          onPressed: editable ? onClearActiveLayer : null,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    );
  }
}

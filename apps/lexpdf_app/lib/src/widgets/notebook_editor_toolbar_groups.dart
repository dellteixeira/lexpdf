import 'package:flutter/material.dart';

import 'notebook_wordpad_chrome.dart';

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
    VoidCallback? enabled(VoidCallback callback) => editable ? callback : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordPadCompactIconButton(tooltip: 'Mover à esquerda', icon: Icons.arrow_left, onPressed: enabled(onMoveLeft)),
            WordPadCompactIconButton(tooltip: 'Mover à direita', icon: Icons.arrow_right, onPressed: enabled(onMoveRight)),
            WordPadCompactIconButton(tooltip: 'Reduzir seleção', icon: Icons.zoom_in_map, onPressed: enabled(onScaleDown)),
            WordPadCompactIconButton(tooltip: 'Ampliar seleção', icon: Icons.zoom_out_map, onPressed: enabled(onScaleUp)),
            WordPadCompactIconButton(tooltip: 'Girar à esquerda', icon: Icons.rotate_left, onPressed: enabled(onRotateLeft)),
            WordPadCompactIconButton(tooltip: 'Girar à direita', icon: Icons.rotate_right, onPressed: enabled(onRotateRight)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordPadCompactIconButton(tooltip: 'Traço mais fino', icon: Icons.remove, onPressed: enabled(onDecreaseWidth)),
            WordPadCompactIconButton(tooltip: 'Traço mais grosso', icon: Icons.add, onPressed: enabled(onIncreaseWidth)),
            WordPadCompactIconButton(tooltip: 'Copiar', icon: Icons.content_copy, onPressed: onCopy),
            WordPadCompactIconButton(tooltip: 'Duplicar', icon: Icons.copy_all_outlined, onPressed: enabled(onDuplicate)),
            WordPadCompactIconButton(tooltip: 'Recortar', icon: Icons.content_cut, onPressed: enabled(onCut)),
            WordPadCompactIconButton(tooltip: 'Reconhecer forma', icon: Icons.auto_awesome_outlined, onPressed: enabled(onRecognize)),
          ],
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
    final canStyle = editable &&
        !eraserMode &&
        (!lassoMode || selectionCount > 0) &&
        (!pointerMode || objectSelected);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WordPadLabeledCommand(
          label: 'Régua',
          icon: Icons.straighten,
          selected: rulerMode,
          onPressed: () => onRulerModeChanged(!rulerMode),
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in palette.take(4))
                  _ColorSwatch(
                    value: value,
                    selected: value == colorValue,
                    enabled: canStyle,
                    onTap: onColorSelected,
                  ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in palette.skip(4))
                  _ColorSwatch(
                    value: value,
                    selected: value == colorValue,
                    enabled: canStyle,
                    onTap: onColorSelected,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(width: 5),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Espessura ${width.toStringAsFixed(1)}', style: const TextStyle(fontSize: 9.5)),
            SizedBox(
              width: 105,
              height: 28,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                ),
                child: Slider(
                  min: 1,
                  max: 10,
                  value: width.clamp(1.0, 10.0).toDouble(),
                  onChanged: canStyle && !lassoMode ? onWidthChanged : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 27,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: stylusOnly,
                    visualDensity: VisualDensity.compact,
                    onChanged: editable ? (value) => onStylusOnlyChanged(value ?? false) : null,
                  ),
                  const Text('Só caneta', style: TextStyle(fontSize: 9.5)),
                ],
              ),
            ),
            WordPadCompactIconButton(
              tooltip: 'Limpar camada ativa',
              icon: Icons.delete_sweep_outlined,
              onPressed: editable ? onClearActiveLayer : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: enabled ? () => onTap(value) : null,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Color(value),
            border: Border.all(
              color: selected ? const Color(0xFF2F66B3) : const Color(0xFF8B8F96),
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

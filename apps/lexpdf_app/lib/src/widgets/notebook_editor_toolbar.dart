import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_object_models.dart';

class NotebookEditorToolbar extends StatelessWidget {
  const NotebookEditorToolbar({
    required this.controller,
    required this.editable,
    required this.pointerMode,
    required this.tool,
    required this.eraserMode,
    required this.lassoMode,
    required this.clipboardAvailable,
    required this.selectionCount,
    required this.rulerMode,
    required this.palette,
    required this.colorValue,
    required this.width,
    required this.stylusOnly,
    required this.selectedObject,
    required this.onPointerModeChanged,
    required this.onToolChanged,
    required this.onEraserModeChanged,
    required this.onLassoModeChanged,
    required this.onMoveSelectionLeft,
    required this.onMoveSelectionRight,
    required this.onScaleSelectionDown,
    required this.onScaleSelectionUp,
    required this.onRotateSelectionLeft,
    required this.onRotateSelectionRight,
    required this.onDecreaseSelectionWidth,
    required this.onIncreaseSelectionWidth,
    required this.onCopySelection,
    required this.onDuplicateSelection,
    required this.onCutSelection,
    required this.onRecognizeSelectedInk,
    required this.onPasteClipboard,
    required this.onAddText,
    required this.onAddShape,
    required this.onAddImage,
    required this.onRotateObjectLeft,
    required this.onRotateObjectRight,
    required this.onEditTextObject,
    required this.onDeleteSelectedObject,
    required this.onRulerModeChanged,
    required this.onColorSelected,
    required this.onWidthChanged,
    required this.onStylusOnlyChanged,
    required this.onClearActiveLayer,
    super.key,
  });

  final ScrollController controller;
  final bool editable;
  final bool pointerMode;
  final InkTool tool;
  final bool eraserMode;
  final bool lassoMode;
  final bool clipboardAvailable;
  final int selectionCount;
  final bool rulerMode;
  final List<int> palette;
  final int colorValue;
  final double width;
  final bool stylusOnly;
  final NotebookObject? selectedObject;

  final ValueChanged<bool> onPointerModeChanged;
  final ValueChanged<InkTool> onToolChanged;
  final ValueChanged<bool> onEraserModeChanged;
  final ValueChanged<bool> onLassoModeChanged;
  final VoidCallback onMoveSelectionLeft;
  final VoidCallback onMoveSelectionRight;
  final VoidCallback onScaleSelectionDown;
  final VoidCallback onScaleSelectionUp;
  final VoidCallback onRotateSelectionLeft;
  final VoidCallback onRotateSelectionRight;
  final VoidCallback onDecreaseSelectionWidth;
  final VoidCallback onIncreaseSelectionWidth;
  final VoidCallback onCopySelection;
  final VoidCallback onDuplicateSelection;
  final VoidCallback onCutSelection;
  final VoidCallback onRecognizeSelectedInk;
  final VoidCallback onPasteClipboard;
  final VoidCallback onAddText;
  final ValueChanged<NotebookObjectType> onAddShape;
  final VoidCallback onAddImage;
  final VoidCallback onRotateObjectLeft;
  final VoidCallback onRotateObjectRight;
  final VoidCallback onEditTextObject;
  final VoidCallback onDeleteSelectedObject;
  final ValueChanged<bool> onRulerModeChanged;
  final ValueChanged<int> onColorSelected;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<bool> onStylusOnlyChanged;
  final VoidCallback onClearActiveLayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget group(List<Widget> children) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 62,
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          trackVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 13),
            child: Row(
              children: [
                group([
                  FilterChip(
                    selected: pointerMode,
                    avatar: const Icon(Icons.near_me_outlined, size: 18),
                    label: const Text('Selecionar'),
                    onSelected: editable ? onPointerModeChanged : null,
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
                    avatar: const Icon(
                      Icons.auto_fix_normal_outlined,
                      size: 18,
                    ),
                    label: const Text('Borracha'),
                    onSelected: editable ? onEraserModeChanged : null,
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    selected: lassoMode,
                    avatar: const Icon(Icons.gesture, size: 18),
                    label: Text(
                      selectionCount > 0 ? 'Laço ($selectionCount)' : 'Laço',
                    ),
                    onSelected: editable ? onLassoModeChanged : null,
                  ),
                ]),
                if (lassoMode && selectionCount > 0) ...[
                  const SizedBox(width: 8),
                  group([
                    IconButton(
                      onPressed: editable ? onMoveSelectionLeft : null,
                      icon: const Icon(Icons.arrow_left),
                    ),
                    IconButton(
                      onPressed: editable ? onMoveSelectionRight : null,
                      icon: const Icon(Icons.arrow_right),
                    ),
                    IconButton(
                      onPressed: editable ? onScaleSelectionDown : null,
                      icon: const Icon(Icons.zoom_in_map),
                    ),
                    IconButton(
                      onPressed: editable ? onScaleSelectionUp : null,
                      icon: const Icon(Icons.zoom_out_map),
                    ),
                    IconButton(
                      onPressed: editable ? onRotateSelectionLeft : null,
                      icon: const Icon(Icons.rotate_left),
                    ),
                    IconButton(
                      onPressed: editable ? onRotateSelectionRight : null,
                      icon: const Icon(Icons.rotate_right),
                    ),
                    IconButton(
                      onPressed: editable ? onDecreaseSelectionWidth : null,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: editable ? onIncreaseSelectionWidth : null,
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      onPressed: onCopySelection,
                      icon: const Icon(Icons.content_copy),
                    ),
                    IconButton(
                      tooltip: 'Duplicar',
                      onPressed: editable ? onDuplicateSelection : null,
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                    IconButton(
                      tooltip: 'Recortar',
                      onPressed: editable ? onCutSelection : null,
                      icon: const Icon(Icons.content_cut),
                    ),
                    IconButton(
                      tooltip: 'Reconhecer forma',
                      onPressed: editable ? onRecognizeSelectedInk : null,
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                  ]),
                ],
                if (lassoMode && clipboardAvailable)
                  IconButton(
                    tooltip: 'Colar',
                    onPressed: editable ? onPasteClipboard : null,
                    icon: const Icon(Icons.content_paste),
                  ),
                const SizedBox(width: 8),
                group([
                  FilledButton.tonalIcon(
                    onPressed: editable ? onAddText : null,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('Texto'),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<NotebookObjectType>(
                    tooltip: 'Inserir forma',
                    icon: const Icon(Icons.add_box_outlined),
                    onSelected: onAddShape,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: NotebookObjectType.line,
                        child: Text('Linha'),
                      ),
                      PopupMenuItem(
                        value: NotebookObjectType.arrow,
                        child: Text('Seta'),
                      ),
                      PopupMenuItem(
                        value: NotebookObjectType.rectangle,
                        child: Text('Retângulo'),
                      ),
                      PopupMenuItem(
                        value: NotebookObjectType.ellipse,
                        child: Text('Elipse'),
                      ),
                      PopupMenuItem(
                        value: NotebookObjectType.triangle,
                        child: Text('Triângulo'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Inserir imagem',
                    onPressed: editable ? onAddImage : null,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  if (selectedObject != null) ...[
                    IconButton(
                      tooltip: 'Girar à esquerda',
                      onPressed: onRotateObjectLeft,
                      icon: const Icon(Icons.rotate_left),
                    ),
                    IconButton(
                      tooltip: 'Girar à direita',
                      onPressed: onRotateObjectRight,
                      icon: const Icon(Icons.rotate_right),
                    ),
                    if (selectedObject!.type == NotebookObjectType.text)
                      IconButton(
                        tooltip: 'Editar texto',
                        onPressed: onEditTextObject,
                        icon: const Icon(Icons.edit_note),
                      ),
                    IconButton(
                      tooltip: 'Excluir objeto',
                      onPressed: onDeleteSelectedObject,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ]),
                const SizedBox(width: 8),
                group([
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
                        onTap:
                            !editable ||
                                eraserMode ||
                                (lassoMode && selectionCount == 0)
                            ? null
                            : () => onColorSelected(value),
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
                ]),
                const SizedBox(width: 8),
                group([
                  const Text('Espessura'),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      min: 1,
                      max: 10,
                      value: width,
                      onChanged:
                          editable &&
                              !eraserMode &&
                              !lassoMode &&
                              !pointerMode
                          ? onWidthChanged
                          : null,
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
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_object_models.dart';

class NotebookEditorToolbar extends StatelessWidget {
  const NotebookEditorToolbar({
    required this.scrollController,
    required this.editable,
    required this.pointerMode,
    required this.tool,
    required this.eraserMode,
    required this.lassoMode,
    required this.selectionCount,
    required this.clipboardAvailable,
    required this.selectedObject,
    required this.rulerMode,
    required this.palette,
    required this.colorValue,
    required this.width,
    required this.stylusOnly,
    required this.lassoTools,
    required this.onPointerModeChanged,
    required this.onToolSelected,
    required this.onEraserChanged,
    required this.onLassoChanged,
    required this.onPasteClipboard,
    required this.onAddText,
    required this.onAddShape,
    required this.onAddImage,
    required this.onRotateSelectedObjectLeft,
    required this.onRotateSelectedObjectRight,
    required this.onEditSelectedText,
    required this.onDeleteSelectedObject,
    required this.onRulerChanged,
    required this.onColorSelected,
    required this.onWidthChanged,
    required this.onStylusOnlyChanged,
    required this.onClearActiveLayer,
    super.key,
  });

  final ScrollController scrollController;
  final bool editable;
  final bool pointerMode;
  final InkTool tool;
  final bool eraserMode;
  final bool lassoMode;
  final int selectionCount;
  final bool clipboardAvailable;
  final NotebookObject? selectedObject;
  final bool rulerMode;
  final List<int> palette;
  final int colorValue;
  final double width;
  final bool stylusOnly;
  final List<Widget> lassoTools;

  final ValueChanged<bool> onPointerModeChanged;
  final ValueChanged<InkTool> onToolSelected;
  final ValueChanged<bool> onEraserChanged;
  final ValueChanged<bool> onLassoChanged;
  final VoidCallback onPasteClipboard;
  final VoidCallback onAddText;
  final ValueChanged<NotebookObjectType> onAddShape;
  final VoidCallback onAddImage;
  final VoidCallback onRotateSelectedObjectLeft;
  final VoidCallback onRotateSelectedObjectRight;
  final VoidCallback onEditSelectedText;
  final VoidCallback onDeleteSelectedObject;
  final ValueChanged<bool> onRulerChanged;
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
          controller: scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: scrollController,
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
                        ? (selection) => onToolSelected(selection.first)
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
                    onSelected: editable ? onEraserChanged : null,
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    selected: lassoMode,
                    avatar: const Icon(Icons.gesture, size: 18),
                    label: Text(
                      selectionCount > 0 ? 'Laço ($selectionCount)' : 'Laço',
                    ),
                    onSelected: editable ? onLassoChanged : null,
                  ),
                ]),
                if (lassoMode && selectionCount > 0) ...[
                  const SizedBox(width: 8),
                  group(lassoTools),
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
                    enabled: editable,
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
                      onPressed: onRotateSelectedObjectLeft,
                      icon: const Icon(Icons.rotate_left),
                    ),
                    IconButton(
                      tooltip: 'Girar à direita',
                      onPressed: onRotateSelectedObjectRight,
                      icon: const Icon(Icons.rotate_right),
                    ),
                    if (selectedObject!.type == NotebookObjectType.text)
                      IconButton(
                        tooltip: 'Editar texto',
                        onPressed: onEditSelectedText,
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
                    onSelected: onRulerChanged,
                  ),
                  const SizedBox(width: 8),
                  for (final value in palette)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: !editable ||
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
                      onChanged: editable &&
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

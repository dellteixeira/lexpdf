import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/notebook/notebook_object_models.dart';
import 'notebook_editor_toolbar_groups.dart';
import 'notebook_ink_controls.dart';
import 'notebook_object_controls.dart';
import 'notebook_wordpad_chrome.dart';

class NotebookEditorToolbar extends StatelessWidget {
  const NotebookEditorToolbar({
    required this.controller,
    required this.editable,
    required this.pointerMode,
    required this.handMode,
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
    required this.onHandModeChanged,
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
    required this.onScaleObjectDown,
    required this.onScaleObjectUp,
    required this.onDuplicateObject,
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
  final bool handMode;
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
  final ValueChanged<bool> onHandModeChanged;
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
  final VoidCallback onScaleObjectDown;
  final VoidCallback onScaleObjectUp;
  final VoidCallback onDuplicateObject;
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
    void addShapeAndSelect(NotebookObjectType type) {
      if (!pointerMode) onPointerModeChanged(true);
      onAddShape(type);
    }

    void addImageAndSelect() {
      if (!pointerMode) onPointerModeChanged(true);
      onAddImage();
    }

    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Ferramentas',
            minWidth: 380,
            child: NotebookInkControls(
              editable: editable,
              pointerMode: pointerMode,
              handMode: handMode,
              tool: tool,
              eraserMode: eraserMode,
              lassoMode: lassoMode,
              selectionCount: selectionCount,
              onPointerModeChanged: onPointerModeChanged,
              onHandModeChanged: onHandModeChanged,
              onToolChanged: onToolChanged,
              onEraserModeChanged: onEraserModeChanged,
              onLassoModeChanged: onLassoModeChanged,
            ),
          ),
          if (lassoMode && selectionCount > 0)
            WordPadRibbonGroup(
              label: 'Seleção',
              minWidth: 175,
              child: NotebookLassoTools(
                editable: editable,
                onMoveLeft: onMoveSelectionLeft,
                onMoveRight: onMoveSelectionRight,
                onScaleDown: onScaleSelectionDown,
                onScaleUp: onScaleSelectionUp,
                onRotateLeft: onRotateSelectionLeft,
                onRotateRight: onRotateSelectionRight,
                onDecreaseWidth: onDecreaseSelectionWidth,
                onIncreaseWidth: onIncreaseSelectionWidth,
                onCopy: onCopySelection,
                onDuplicate: onDuplicateSelection,
                onCut: onCutSelection,
                onRecognize: onRecognizeSelectedInk,
              ),
            ),
          if (lassoMode && clipboardAvailable)
            WordPadRibbonGroup(
              label: 'Área de transferência',
              minWidth: 70,
              child: WordPadLabeledCommand(
                label: 'Colar',
                icon: Icons.content_paste,
                onPressed: editable ? onPasteClipboard : null,
              ),
            ),
          WordPadRibbonGroup(
            label: 'Inserir e objeto',
            minWidth: selectedObject == null ? 175 : 360,
            child: NotebookObjectControls(
              editable: editable,
              selectedObject: selectedObject,
              onAddText: onAddText,
              onAddShape: addShapeAndSelect,
              onAddImage: addImageAndSelect,
              onScaleDown: onScaleObjectDown,
              onScaleUp: onScaleObjectUp,
              onDuplicate: onDuplicateObject,
              onRotateLeft: onRotateObjectLeft,
              onRotateRight: onRotateObjectRight,
              onEditText: onEditTextObject,
              onDelete: onDeleteSelectedObject,
            ),
          ),
          WordPadRibbonGroup(
            label: 'Estilo',
            minWidth: 330,
            child: NotebookStyleControls(
              editable: editable,
              pointerMode: pointerMode,
              objectSelected: selectedObject != null,
              eraserMode: eraserMode,
              lassoMode: lassoMode,
              selectionCount: selectionCount,
              rulerMode: rulerMode,
              palette: palette,
              colorValue: colorValue,
              width: width,
              stylusOnly: stylusOnly,
              onRulerModeChanged: onRulerModeChanged,
              onColorSelected: onColorSelected,
              onWidthChanged: onWidthChanged,
              onStylusOnlyChanged: onStylusOnlyChanged,
              onClearActiveLayer: onClearActiveLayer,
            ),
          ),
        ],
      ),
    );
  }
}

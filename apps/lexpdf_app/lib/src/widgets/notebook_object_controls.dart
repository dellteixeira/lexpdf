import 'package:flutter/material.dart';

import '../core/notebook/notebook_object_models.dart';
import 'notebook_wordpad_chrome.dart';

class NotebookObjectControls extends StatelessWidget {
  const NotebookObjectControls({
    required this.editable,
    required this.selectedObject,
    required this.onAddText,
    required this.onAddShape,
    required this.onAddImage,
    required this.onScaleDown,
    required this.onScaleUp,
    required this.onDuplicate,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onEditText,
    required this.onDelete,
    super.key,
  });

  final bool editable;
  final NotebookObject? selectedObject;
  final VoidCallback onAddText;
  final ValueChanged<NotebookObjectType> onAddShape;
  final VoidCallback onAddImage;
  final VoidCallback onScaleDown;
  final VoidCallback onScaleUp;
  final VoidCallback onDuplicate;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onEditText;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final selected = selectedObject;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WordPadLabeledCommand(
          label: 'Texto',
          icon: Icons.text_fields,
          onPressed: editable ? onAddText : null,
        ),
        PopupMenuButton<NotebookObjectType>(
          tooltip: 'Inserir forma',
          onSelected: onAddShape,
          itemBuilder: (_) => const [
            PopupMenuItem(value: NotebookObjectType.line, child: Text('Linha reta')),
            PopupMenuItem(value: NotebookObjectType.arrow, child: Text('Seta')),
            PopupMenuItem(value: NotebookObjectType.rectangle, child: Text('Retângulo')),
            PopupMenuItem(value: NotebookObjectType.ellipse, child: Text('Elipse')),
            PopupMenuItem(value: NotebookObjectType.triangle, child: Text('Triângulo')),
          ],
          child: const SizedBox(
            width: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_box_outlined, size: 22),
                SizedBox(height: 2),
                Text('Forma', style: TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
        ),
        WordPadLabeledCommand(
          label: 'Imagem',
          icon: Icons.add_photo_alternate_outlined,
          onPressed: editable ? onAddImage : null,
        ),
        if (selected != null) ...[
          const SizedBox(width: 4),
          Container(width: 1, height: 44, color: const Color(0xFFD5D8DE)),
          const SizedBox(width: 4),
          WordPadCompactIconButton(
            tooltip: 'Diminuir ${_selectionLabel(selected.type)}',
            icon: Icons.zoom_in_map,
            onPressed: editable ? onScaleDown : null,
          ),
          WordPadCompactIconButton(
            tooltip: 'Aumentar ${_selectionLabel(selected.type)}',
            icon: Icons.zoom_out_map,
            onPressed: editable ? onScaleUp : null,
          ),
          WordPadCompactIconButton(
            tooltip: 'Duplicar ${_selectionLabel(selected.type)}',
            icon: Icons.copy_all_outlined,
            onPressed: editable ? onDuplicate : null,
          ),
          WordPadCompactIconButton(
            tooltip: 'Girar à esquerda',
            icon: Icons.rotate_left,
            onPressed: editable ? onRotateLeft : null,
          ),
          WordPadCompactIconButton(
            tooltip: 'Girar à direita',
            icon: Icons.rotate_right,
            onPressed: editable ? onRotateRight : null,
          ),
          if (selected.type == NotebookObjectType.text)
            WordPadCompactIconButton(
              tooltip: 'Editar texto',
              icon: Icons.edit_note,
              onPressed: editable ? onEditText : null,
            ),
          WordPadCompactIconButton(
            tooltip: 'Excluir ${_selectionLabel(selected.type)}',
            icon: Icons.delete_outline,
            onPressed: editable ? onDelete : null,
          ),
        ],
      ],
    );
  }

  static String _selectionLabel(NotebookObjectType type) => switch (type) {
        NotebookObjectType.text => 'texto',
        NotebookObjectType.image => 'imagem',
        NotebookObjectType.line => 'linha',
        NotebookObjectType.arrow => 'seta',
        NotebookObjectType.rectangle => 'retângulo',
        NotebookObjectType.ellipse => 'elipse',
        NotebookObjectType.triangle => 'triângulo',
      };
}

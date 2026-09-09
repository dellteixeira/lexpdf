import 'package:flutter/material.dart';

import '../core/notebook/notebook_object_models.dart';

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
        if (selected != null) ...[
          Chip(
            avatar: const Icon(Icons.select_all, size: 17),
            label: Text(_selectionLabel(selected.type)),
          ),
          IconButton(
            tooltip: 'Diminuir objeto selecionado',
            onPressed: editable ? onScaleDown : null,
            icon: const Icon(Icons.zoom_in_map),
          ),
          IconButton(
            tooltip: 'Aumentar objeto selecionado',
            onPressed: editable ? onScaleUp : null,
            icon: const Icon(Icons.zoom_out_map),
          ),
          IconButton(
            tooltip: 'Duplicar objeto selecionado',
            onPressed: editable ? onDuplicate : null,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Girar à esquerda',
            onPressed: editable ? onRotateLeft : null,
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            tooltip: 'Girar à direita',
            onPressed: editable ? onRotateRight : null,
            icon: const Icon(Icons.rotate_right),
          ),
          if (selected.type == NotebookObjectType.text)
            IconButton(
              tooltip: 'Editar texto selecionado',
              onPressed: editable ? onEditText : null,
              icon: const Icon(Icons.edit_note),
            ),
          FilledButton.tonalIcon(
            onPressed: editable ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
          const VerticalDivider(width: 18),
        ],
        FilledButton.tonalIcon(
          onPressed: editable ? onAddText : null,
          icon: const Icon(Icons.text_fields),
          label: const Text('Texto'),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<NotebookObjectType>(
          tooltip: 'Inserir forma e selecionar',
          icon: const Icon(Icons.add_box_outlined),
          onSelected: onAddShape,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: NotebookObjectType.line,
              child: Text('Linha reta'),
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
          tooltip: 'Inserir imagem e selecionar',
          onPressed: editable ? onAddImage : null,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
      ],
    );
  }

  String _selectionLabel(NotebookObjectType type) => switch (type) {
        NotebookObjectType.text => 'Texto selecionado',
        NotebookObjectType.image => 'Imagem selecionada',
        NotebookObjectType.line => 'Linha selecionada',
        NotebookObjectType.arrow => 'Seta selecionada',
        NotebookObjectType.rectangle => 'Retângulo selecionado',
        NotebookObjectType.ellipse => 'Elipse selecionada',
        NotebookObjectType.triangle => 'Triângulo selecionado',
      };
}

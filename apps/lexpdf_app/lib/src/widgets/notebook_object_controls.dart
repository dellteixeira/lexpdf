import 'package:flutter/material.dart';

import '../core/notebook/notebook_object_models.dart';

class NotebookObjectControls extends StatelessWidget {
  const NotebookObjectControls({
    required this.editable,
    required this.selectedObject,
    required this.onAddText,
    required this.onAddShape,
    required this.onAddImage,
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
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onEditText;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
            onPressed: onRotateLeft,
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            tooltip: 'Girar à direita',
            onPressed: onRotateRight,
            icon: const Icon(Icons.rotate_right),
          ),
          if (selectedObject!.type == NotebookObjectType.text)
            IconButton(
              tooltip: 'Editar texto',
              onPressed: onEditText,
              icon: const Icon(Icons.edit_note),
            ),
          IconButton(
            tooltip: 'Excluir objeto',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
    );
  }
}

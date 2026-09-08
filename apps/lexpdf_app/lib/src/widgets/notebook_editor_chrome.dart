import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_notebook_layer_store.dart';

class NotebookNavigationBar extends StatelessWidget {
  const NotebookNavigationBar({
    required this.notebooks,
    required this.currentNotebook,
    required this.currentPage,
    required this.pageIndex,
    required this.pageCount,
    required this.backgroundLabel,
    required this.onNotebookChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onAddPage,
    required this.onDuplicatePage,
    required this.onMovePageLeft,
    required this.onMovePageRight,
    required this.onDeletePage,
    required this.onBackgroundChanged,
    super.key,
  });

  final List<InkNotebook> notebooks;
  final InkNotebook? currentNotebook;
  final InkNotebookPage? currentPage;
  final int pageIndex;
  final int pageCount;
  final String Function(InkPageBackground) backgroundLabel;
  final ValueChanged<String> onNotebookChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback onAddPage;
  final VoidCallback? onDuplicatePage;
  final VoidCallback? onMovePageLeft;
  final VoidCallback? onMovePageRight;
  final VoidCallback? onDeletePage;
  final ValueChanged<InkPageBackground> onBackgroundChanged;

  @override
  Widget build(BuildContext context) {
    final page = currentPage;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            DropdownButton<String>(
              value: currentNotebook?.id,
              items: notebooks
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.title),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) onNotebookChanged(id);
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Página anterior',
              onPressed: onPreviousPage,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Página ${page?.pageNumber ?? 0} de $pageCount'),
            IconButton(
              tooltip: 'Próxima página',
              onPressed: onNextPage,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Adicionar página',
              onPressed: onAddPage,
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              tooltip: 'Duplicar página',
              onPressed: onDuplicatePage,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: 'Mover página para a esquerda',
              onPressed: onMovePageLeft,
              icon: const Icon(Icons.keyboard_double_arrow_left),
            ),
            IconButton(
              tooltip: 'Mover página para a direita',
              onPressed: onMovePageRight,
              icon: const Icon(Icons.keyboard_double_arrow_right),
            ),
            IconButton(
              tooltip: 'Excluir página',
              onPressed: onDeletePage,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 12),
            DropdownButton<InkPageBackground>(
              value: page?.background,
              hint: const Text('Template'),
              items: InkPageBackground.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(backgroundLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onBackgroundChanged(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class NotebookLayerStatus extends StatelessWidget {
  const NotebookLayerStatus({
    required this.layer,
    required this.layerCount,
    required this.onTap,
    super.key,
  });

  final NotebookLayer layer;
  final int layerCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.layers_outlined, size: 18),
              const SizedBox(width: 8),
              Text('Camada ativa: ${layer.name}'),
              const SizedBox(width: 8),
              if (!layer.isVisible) const Chip(label: Text('Oculta')),
              if (layer.isLocked) const Chip(label: Text('Bloqueada')),
              const Spacer(),
              Text('$layerCount camada(s)'),
            ],
          ),
        ),
      ),
    );
  }
}

class NotebookZoomControls extends StatelessWidget {
  const NotebookZoomControls({
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
    super.key,
  });

  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Diminuir zoom',
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove),
            ),
            Text('${(zoom * 100).round()}%'),
            IconButton(
              tooltip: 'Aumentar zoom',
              onPressed: onZoomIn,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Ajustar página',
              onPressed: onReset,
              icon: const Icon(Icons.fit_screen_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

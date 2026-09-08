import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';
import '../core/storage/local_notebook_layer_store.dart';

enum _NotebookPageAction {
  add,
  duplicate,
  moveLeft,
  moveRight,
  delete,
}

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
    final compact = MediaQuery.sizeOf(context).width < 760;
    final page = currentPage;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentNotebook?.id,
                  isExpanded: compact,
                  borderRadius: BorderRadius.circular(12),
                  items: notebooks
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) onNotebookChanged(id);
                  },
                ),
              ),
            ),
            if (!compact) const SizedBox(width: 12),
            IconButton(
              tooltip: 'Página anterior',
              onPressed: onPreviousPage,
              icon: const Icon(Icons.chevron_left),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${page?.pageNumber ?? 0}/$pageCount',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Próxima página',
              onPressed: onNextPage,
              icon: const Icon(Icons.chevron_right),
            ),
            if (compact) ...[
              PopupMenuButton<_NotebookPageAction>(
                tooltip: 'Ações da página',
                icon: const Icon(Icons.more_vert),
                onSelected: _handlePageAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _NotebookPageAction.add,
                    child: _MenuLabel(
                      icon: Icons.note_add_outlined,
                      label: 'Adicionar página',
                    ),
                  ),
                  PopupMenuItem(
                    value: _NotebookPageAction.duplicate,
                    enabled: onDuplicatePage != null,
                    child: const _MenuLabel(
                      icon: Icons.copy_all_outlined,
                      label: 'Duplicar página',
                    ),
                  ),
                  PopupMenuItem(
                    value: _NotebookPageAction.moveLeft,
                    enabled: onMovePageLeft != null,
                    child: const _MenuLabel(
                      icon: Icons.keyboard_arrow_left,
                      label: 'Mover para a esquerda',
                    ),
                  ),
                  PopupMenuItem(
                    value: _NotebookPageAction.moveRight,
                    enabled: onMovePageRight != null,
                    child: const _MenuLabel(
                      icon: Icons.keyboard_arrow_right,
                      label: 'Mover para a direita',
                    ),
                  ),
                  PopupMenuItem(
                    value: _NotebookPageAction.delete,
                    enabled: onDeletePage != null,
                    child: const _MenuLabel(
                      icon: Icons.delete_outline,
                      label: 'Excluir página',
                    ),
                  ),
                ],
              ),
              PopupMenuButton<InkPageBackground>(
                tooltip: 'Template da página',
                icon: const Icon(Icons.dashboard_customize_outlined),
                onSelected: onBackgroundChanged,
                itemBuilder: (context) => InkPageBackground.values
                    .map(
                      (value) => PopupMenuItem(
                        value: value,
                        child: Text(backgroundLabel(value)),
                      ),
                    )
                    .toList(),
              ),
            ] else ...[
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
                icon: const Icon(Icons.keyboard_arrow_left),
              ),
              IconButton(
                tooltip: 'Mover página para a direita',
                onPressed: onMovePageRight,
                icon: const Icon(Icons.keyboard_arrow_right),
              ),
              IconButton(
                tooltip: 'Excluir página',
                onPressed: onDeletePage,
                icon: const Icon(Icons.delete_outline),
              ),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<InkPageBackground>(
                  value: page?.background,
                  hint: const Text('Template'),
                  borderRadius: BorderRadius.circular(12),
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
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  void _handlePageAction(_NotebookPageAction action) {
    switch (action) {
      case _NotebookPageAction.add:
        onAddPage();
        break;
      case _NotebookPageAction.duplicate:
        onDuplicatePage?.call();
        break;
      case _NotebookPageAction.moveLeft:
        onMovePageLeft?.call();
        break;
      case _NotebookPageAction.moveRight:
        onMovePageRight?.call();
        break;
      case _NotebookPageAction.delete:
        onDeletePage?.call();
        break;
    }
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Row(
            children: [
              const Icon(Icons.layers_outlined, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (!layer.isVisible) ...[
                const SizedBox(width: 6),
                const Icon(Icons.visibility_off_outlined, size: 16),
              ],
              if (layer.isLocked) ...[
                const SizedBox(width: 6),
                const Icon(Icons.lock_outline, size: 16),
              ],
              const SizedBox(width: 8),
              Text(
                '$layerCount',
                style: Theme.of(context).textTheme.labelSmall,
              ),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: scheme.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuir zoom',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          Text(
            '${(zoom * 100).round()}%',
            style: Theme.of(context).textTheme.labelMedium,
          ),
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
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

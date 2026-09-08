import 'package:flutter/material.dart';

enum _ReaderAction {
  study,
  annotationPalette,
  annotations,
  inkSummary,
  configureInk,
}

class PdfReaderAppBarActions extends StatelessWidget {
  const PdfReaderAppBarActions({
    required this.currentPage,
    required this.inkMode,
    required this.inkEraserMode,
    required this.annotationCount,
    required this.inkCount,
    required this.onToggleInkMode,
    required this.onToggleEraser,
    required this.onConfigureInk,
    required this.onUndoInk,
    required this.onOpenStudy,
    required this.onOpenSearch,
    required this.onOpenAnnotationPalette,
    required this.onOpenAnnotations,
    required this.onOpenInkSummary,
    super.key,
  });

  final int? currentPage;
  final bool inkMode;
  final bool inkEraserMode;
  final int annotationCount;
  final int inkCount;
  final VoidCallback onToggleInkMode;
  final VoidCallback onToggleEraser;
  final VoidCallback? onConfigureInk;
  final VoidCallback onUndoInk;
  final VoidCallback onOpenStudy;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenAnnotationPalette;
  final VoidCallback onOpenAnnotations;
  final VoidCallback onOpenInkSummary;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final primary = Theme.of(context).colorScheme.primary;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentPage != null) _PagePill(page: currentPage!),
          _ReaderIconButton(
            tooltip: inkMode ? 'Sair do modo escrita' : 'Escrever no PDF',
            onPressed: onToggleInkMode,
            icon: inkMode ? Icons.edit_off_outlined : Icons.edit_outlined,
            selected: inkMode,
          ),
          if (inkMode) ...[
            _ReaderIconButton(
              tooltip: inkEraserMode ? 'Voltar para caneta' : 'Borracha parcial',
              onPressed: onToggleEraser,
              icon: inkEraserMode ? Icons.edit_outlined : Icons.auto_fix_off,
              selected: inkEraserMode,
            ),
            _ReaderIconButton(
              tooltip: 'Desfazer último traço desta página',
              onPressed: onUndoInk,
              icon: Icons.undo,
            ),
          ] else
            _ReaderIconButton(
              tooltip: 'Pesquisar no PDF',
              onPressed: onOpenSearch,
              icon: Icons.search,
            ),
          PopupMenuButton<_ReaderAction>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert),
            onSelected: _handleAction,
            itemBuilder: (context) => inkMode
                ? [
                    PopupMenuItem(
                      value: _ReaderAction.configureInk,
                      enabled: onConfigureInk != null,
                      child: const _MenuLabel(
                        icon: Icons.tune,
                        label: 'Ajustar escrita',
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.inkSummary,
                      child: _MenuLabel(
                        icon: Icons.gesture_outlined,
                        label: inkCount > 0
                            ? 'Traços manuscritos · $inkCount'
                            : 'Traços manuscritos',
                      ),
                    ),
                  ]
                : [
                    const PopupMenuItem(
                      value: _ReaderAction.study,
                      child: _MenuLabel(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Estudar documento',
                      ),
                    ),
                    const PopupMenuItem(
                      value: _ReaderAction.annotationPalette,
                      child: _MenuLabel(
                        icon: Icons.palette_outlined,
                        label: 'Cor das marcações',
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.annotations,
                      child: _MenuLabel(
                        icon: Icons.draw_outlined,
                        label: annotationCount > 0
                            ? 'Anotações textuais · $annotationCount'
                            : 'Anotações textuais',
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.inkSummary,
                      child: _MenuLabel(
                        icon: Icons.gesture_outlined,
                        label: inkCount > 0
                            ? 'Traços manuscritos · $inkCount'
                            : 'Traços manuscritos',
                      ),
                    ),
                  ],
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentPage != null) _PagePill(page: currentPage!),
        _ReaderIconButton(
          tooltip: inkMode ? 'Sair do modo escrita' : 'Escrever no PDF',
          onPressed: onToggleInkMode,
          icon: inkMode ? Icons.edit_off_outlined : Icons.edit_outlined,
          selected: inkMode,
        ),
        if (inkMode) ...[
          _ReaderIconButton(
            tooltip: inkEraserMode ? 'Voltar para caneta' : 'Borracha parcial',
            onPressed: onToggleEraser,
            icon: inkEraserMode ? Icons.edit_outlined : Icons.auto_fix_off,
            selected: inkEraserMode,
          ),
          _ReaderIconButton(
            tooltip: 'Configurar caneta',
            onPressed: onConfigureInk,
            icon: Icons.tune,
          ),
          _ReaderIconButton(
            tooltip: 'Desfazer último traço desta página',
            onPressed: onUndoInk,
            icon: Icons.undo,
          ),
        ] else ...[
          _ReaderIconButton(
            tooltip: 'Estudar documento',
            onPressed: onOpenStudy,
            icon: Icons.auto_awesome_outlined,
          ),
          _ReaderIconButton(
            tooltip: 'Pesquisar no PDF',
            onPressed: onOpenSearch,
            icon: Icons.search,
          ),
          _ReaderIconButton(
            tooltip: 'Cor das novas marcações',
            onPressed: onOpenAnnotationPalette,
            icon: Icons.palette_outlined,
          ),
          Badge(
            isLabelVisible: annotationCount > 0,
            label: Text('$annotationCount'),
            child: _ReaderIconButton(
              tooltip: 'Anotações textuais',
              onPressed: onOpenAnnotations,
              icon: Icons.draw_outlined,
            ),
          ),
        ],
        Badge(
          isLabelVisible: inkCount > 0,
          label: Text('$inkCount'),
          child: _ReaderIconButton(
            tooltip: 'Traços manuscritos',
            onPressed: onOpenInkSummary,
            icon: Icons.gesture_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Imprimir',
          onPressed: null,
          icon: Icon(Icons.print_outlined, color: primary.withValues(alpha: 0.42)),
        ),
      ],
    );
  }

  void _handleAction(_ReaderAction action) {
    switch (action) {
      case _ReaderAction.study:
        onOpenStudy();
        return;
      case _ReaderAction.annotationPalette:
        onOpenAnnotationPalette();
        return;
      case _ReaderAction.annotations:
        onOpenAnnotations();
        return;
      case _ReaderAction.inkSummary:
        onOpenInkSummary();
        return;
      case _ReaderAction.configureInk:
        onConfigureInk?.call();
        return;
    }
  }
}

class PdfSearchAppBarActions extends StatelessWidget {
  const PdfSearchAppBarActions({
    required this.isSearching,
    required this.currentIndex,
    required this.matchCount,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    super.key,
  });

  final bool isSearching;
  final int? currentIndex;
  final int matchCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            child: Text(
              isSearching
                  ? 'Buscando…'
                  : matchCount == 0
                      ? '0'
                      : '${(currentIndex ?? 0) + 1}/$matchCount',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        _ReaderIconButton(
          tooltip: 'Resultado anterior',
          onPressed: onPrevious,
          icon: Icons.keyboard_arrow_up,
        ),
        _ReaderIconButton(
          tooltip: 'Próximo resultado',
          onPressed: onNext,
          icon: Icons.keyboard_arrow_down,
        ),
        _ReaderIconButton(
          tooltip: 'Fechar pesquisa',
          onPressed: onClose,
          icon: Icons.close,
        ),
      ],
    );
  }
}

class PdfInkStatusCard extends StatelessWidget {
  const PdfInkStatusCard({
    required this.eraserMode,
    required this.colorValue,
    required this.toolLabel,
    required this.width,
    required this.onConfigure,
    super.key,
  });

  final bool eraserMode;
  final int colorValue;
  final String toolLabel;
  final double width;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 7, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              eraserMode ? Icons.auto_fix_off : Icons.edit_outlined,
              size: 18,
              color: eraserMode ? scheme.onSurfaceVariant : Color(colorValue),
            ),
            const SizedBox(width: 8),
            Text(
              eraserMode
                  ? 'Borracha'
                  : '$toolLabel · ${width.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Ajustar escrita',
              onPressed: onConfigure,
              icon: const Icon(Icons.tune, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$page',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ReaderIconButton extends StatelessWidget {
  const _ReaderIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.selected = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: selected
          ? IconButton.styleFrom(
              foregroundColor: scheme.primary,
              backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
            )
          : null,
      icon: Icon(icon),
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
        Flexible(child: Text(label)),
      ],
    );
  }
}

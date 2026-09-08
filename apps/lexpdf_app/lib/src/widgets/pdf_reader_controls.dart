import 'package:flutter/material.dart';

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
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentPage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('Pág. $currentPage')),
          ),
        IconButton(
          tooltip: inkMode ? 'Sair do modo escrita' : 'Escrever no PDF',
          onPressed: onToggleInkMode,
          icon: Icon(inkMode ? Icons.edit_off_outlined : Icons.edit_outlined),
          color: inkMode ? primary : null,
        ),
        if (inkMode) ...[
          IconButton(
            tooltip: inkEraserMode ? 'Voltar para caneta' : 'Borracha parcial',
            onPressed: onToggleEraser,
            icon: Icon(
              inkEraserMode ? Icons.edit_outlined : Icons.auto_fix_off,
            ),
            color: inkEraserMode ? primary : null,
          ),
          IconButton(
            tooltip: 'Configurar caneta',
            onPressed: onConfigureInk,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Desfazer último traço desta página',
            onPressed: onUndoInk,
            icon: const Icon(Icons.undo),
          ),
        ] else ...[
          IconButton(
            tooltip: 'Estudar documento',
            onPressed: onOpenStudy,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Pesquisar no PDF',
            onPressed: onOpenSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Cor das novas marcações',
            onPressed: onOpenAnnotationPalette,
            icon: const Icon(Icons.palette_outlined),
          ),
          Badge(
            isLabelVisible: annotationCount > 0,
            label: Text('$annotationCount'),
            child: IconButton(
              tooltip: 'Anotações textuais',
              onPressed: onOpenAnnotations,
              icon: const Icon(Icons.draw_outlined),
            ),
          ),
        ],
        Badge(
          isLabelVisible: inkCount > 0,
          label: Text('$inkCount'),
          child: IconButton(
            tooltip: 'Traços manuscritos',
            onPressed: onOpenInkSummary,
            icon: const Icon(Icons.gesture_outlined),
          ),
        ),
        const IconButton(
          tooltip: 'Imprimir',
          onPressed: null,
          icon: Icon(Icons.print_outlined),
        ),
      ],
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              isSearching
                  ? 'Buscando…'
                  : matchCount == 0
                      ? '0 resultados'
                      : '${(currentIndex ?? 0) + 1}/$matchCount',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Resultado anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'Próximo resultado',
          onPressed: onNext,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          tooltip: 'Fechar pesquisa',
          onPressed: onClose,
          icon: const Icon(Icons.close),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              eraserMode ? Icons.auto_fix_off : Icons.edit,
              color: eraserMode ? null : Color(colorValue),
            ),
            const SizedBox(width: 8),
            Text(
              eraserMode
                  ? 'Borracha parcial'
                  : '$toolLabel · ${width.toStringAsFixed(1)}',
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.tune),
              label: const Text('Ajustar'),
            ),
          ],
        ),
      ),
    );
  }
}

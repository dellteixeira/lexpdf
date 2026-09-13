import 'package:flutter/material.dart';

enum NotebookRibbonTab { home, drawing, view }

class NotebookWordPadRibbon extends StatelessWidget {
  const NotebookWordPadRibbon({
    required this.activeTab,
    required this.onTabChanged,
    required this.onFilePressed,
    required this.home,
    required this.drawing,
    required this.view,
    super.key,
  });

  final NotebookRibbonTab activeTab;
  final ValueChanged<NotebookRibbonTab> onTabChanged;
  final VoidCallback onFilePressed;
  final Widget home;
  final Widget drawing;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final content = switch (activeTab) {
      NotebookRibbonTab.home => home,
      NotebookRibbonTab.drawing => drawing,
      NotebookRibbonTab.view => view,
    };

    Widget tab(String label, NotebookRibbonTab value) {
      final selected = activeTab == value;
      return InkWell(
        onTap: () => onTabChanged(value),
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 72 : 92),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 39,
            child: Row(
              children: [
                InkWell(
                  onTap: onFilePressed,
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    color: scheme.primary,
                    child: Text(
                      'Arquivo',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                tab('Início', NotebookRibbonTab.home),
                tab('Desenho', NotebookRibbonTab.drawing),
                tab('Exibir', NotebookRibbonTab.view),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            height: compact ? 94 : 112,
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                top: BorderSide(color: scheme.outlineVariant),
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: content,
          ),
        ],
      ),
    );
  }
}

class WordPadRibbonGroup extends StatelessWidget {
  const WordPadRibbonGroup({
    required this.label,
    required this.child,
    this.minWidth = 96,
    super.key,
  });

  final String label;
  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Center(child: child)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class WordPadLargeAction extends StatelessWidget {
  const WordPadLargeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class NotebookWordPadRuler extends StatelessWidget {
  const NotebookWordPadRuler({
    required this.visible,
    super.key,
  });

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: CustomPaint(
        painter: _NotebookWordPadRulerPainter(
          foreground: scheme.onSurfaceVariant,
          line: scheme.outlineVariant,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NotebookWordPadRulerPainter extends CustomPainter {
  const _NotebookWordPadRulerPainter({
    required this.foreground,
    required this.line,
  });

  final Color foreground;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = line
      ..strokeWidth = 1;
    final ticks = Paint()
      ..color = foreground.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    const majorCount = 18;
    final step = size.width / majorCount;
    final textStyle = TextStyle(fontSize: 9, height: 1);
    for (var index = 0; index <= majorCount; index++) {
      final x = index * step;
      canvas.drawLine(
        Offset(x, size.height - 10),
        Offset(x, size.height - 1),
        ticks,
      );
      if (index > 0 && index < majorCount) {
        final painter = TextPainter(
          text: TextSpan(
            text: '$index',
            style: textStyle.copyWith(color: foreground),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x - painter.width / 2, 2));
      }
      if (index < majorCount) {
        for (var minor = 1; minor < 4; minor++) {
          final minorX = x + (step * minor / 4);
          final length = minor == 2 ? 6.0 : 4.0;
          canvas.drawLine(
            Offset(minorX, size.height - length),
            Offset(minorX, size.height - 1),
            ticks,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookWordPadRulerPainter oldDelegate) =>
      oldDelegate.foreground != foreground || oldDelegate.line != line;
}

class NotebookWordPadStatusBar extends StatelessWidget {
  const NotebookWordPadStatusBar({
    required this.pageIndex,
    required this.pageCount,
    required this.zoom,
    required this.onZoomChanged,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onResetZoom,
    super.key,
  });

  final int pageIndex;
  final int pageCount;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onResetZoom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Material(
      color: scheme.surface,
      child: Container(
        height: compact ? 42 : 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Text(
              'Página ${pageIndex + 1} de $pageCount',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Diminuir zoom',
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove, size: 18),
            ),
            InkWell(
              onTap: onResetZoom,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  '${(zoom * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            SizedBox(
              width: compact ? 84 : 150,
              child: Slider(
                value: zoom.clamp(0.25, 4.0),
                min: 0.25,
                max: 4.0,
                onChanged: onZoomChanged,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Aumentar zoom',
              onPressed: onZoomIn,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

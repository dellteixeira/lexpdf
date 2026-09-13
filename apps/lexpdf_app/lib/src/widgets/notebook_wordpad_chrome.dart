import 'package:flutter/material.dart';

enum NotebookRibbonTab { home, drawing, view }

enum _NotebookFileAction {
  openDocument,
  saveDocx,
  saveTxt,
  exportPdf,
  saveDoc,
  saveRtf,
  newNotebook,
  renameNotebook,
  deleteNotebook,
  newPage,
  duplicatePage,
  deletePage,
}

class NotebookWordPadScaffold extends StatefulWidget {
  const NotebookWordPadScaffold({
    required this.title,
    required this.homeRibbon,
    required this.drawingRibbon,
    required this.viewRibbon,
    required this.document,
    required this.pageIndex,
    required this.pageCount,
    required this.wordCount,
    required this.layerName,
    required this.zoom,
    required this.showDocumentRuler,
    required this.onOpenDocument,
    required this.onSaveDocx,
    required this.onSaveTxt,
    required this.onExportPdf,
    required this.onSaveDoc,
    required this.onSaveRtf,
    required this.onNewNotebook,
    required this.onRenameNotebook,
    required this.onDeleteNotebook,
    required this.onNewPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onLayers,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onUndo,
    required this.onRedo,
    required this.onZoomChanged,
    required this.onFitPage,
    this.onRibbonTabChanged,
    super.key,
  });

  final String title;
  final Widget homeRibbon;
  final Widget drawingRibbon;
  final Widget viewRibbon;
  final Widget document;
  final int pageIndex;
  final int pageCount;
  final int wordCount;
  final String layerName;
  final double zoom;
  final bool showDocumentRuler;
  final VoidCallback onOpenDocument;
  final VoidCallback onSaveDocx;
  final VoidCallback onSaveTxt;
  final VoidCallback onExportPdf;
  final VoidCallback onSaveDoc;
  final VoidCallback onSaveRtf;
  final VoidCallback onNewNotebook;
  final VoidCallback onRenameNotebook;
  final VoidCallback? onDeleteNotebook;
  final VoidCallback onNewPage;
  final VoidCallback? onDuplicatePage;
  final VoidCallback? onDeletePage;
  final VoidCallback onLayers;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onFitPage;
  final ValueChanged<NotebookRibbonTab>? onRibbonTabChanged;

  @override
  State<NotebookWordPadScaffold> createState() =>
      _NotebookWordPadScaffoldState();
}

class _NotebookWordPadScaffoldState extends State<NotebookWordPadScaffold> {
  NotebookRibbonTab _tab = NotebookRibbonTab.home;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE7E9ED),
      child: Column(
        children: [
          _WordPadTitleBar(
            title: widget.title,
            onUndo: widget.onUndo,
            onRedo: widget.onRedo,
            onLayers: widget.onLayers,
          ),
          _WordPadTabStrip(
            activeTab: _tab,
            onTabChanged: (value) {
              setState(() => _tab = value);
              widget.onRibbonTabChanged?.call(value);
            },
            onFileAction: _handleFileAction,
            canDeleteNotebook: widget.onDeleteNotebook != null,
            canDuplicatePage: widget.onDuplicatePage != null,
            canDeletePage: widget.onDeletePage != null,
          ),
          Container(
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFC9CDD4))),
            ),
            child: switch (_tab) {
              NotebookRibbonTab.home => widget.homeRibbon,
              NotebookRibbonTab.drawing => widget.drawingRibbon,
              NotebookRibbonTab.view => widget.viewRibbon,
            },
          ),
          if (widget.showDocumentRuler) const NotebookDocumentRuler(),
          Expanded(child: widget.document),
          NotebookWordPadStatusBar(
            pageIndex: widget.pageIndex,
            pageCount: widget.pageCount,
            wordCount: widget.wordCount,
            layerName: widget.layerName,
            zoom: widget.zoom,
            onPreviousPage: widget.onPreviousPage,
            onNextPage: widget.onNextPage,
            onZoomChanged: widget.onZoomChanged,
            onFitPage: widget.onFitPage,
          ),
        ],
      ),
    );
  }

  void _handleFileAction(_NotebookFileAction action) {
    switch (action) {
      case _NotebookFileAction.openDocument:
        widget.onOpenDocument();
      case _NotebookFileAction.saveDocx:
        widget.onSaveDocx();
      case _NotebookFileAction.saveTxt:
        widget.onSaveTxt();
      case _NotebookFileAction.exportPdf:
        widget.onExportPdf();
      case _NotebookFileAction.saveDoc:
        widget.onSaveDoc();
      case _NotebookFileAction.saveRtf:
        widget.onSaveRtf();
      case _NotebookFileAction.newNotebook:
        widget.onNewNotebook();
      case _NotebookFileAction.renameNotebook:
        widget.onRenameNotebook();
      case _NotebookFileAction.deleteNotebook:
        widget.onDeleteNotebook?.call();
      case _NotebookFileAction.newPage:
        widget.onNewPage();
      case _NotebookFileAction.duplicatePage:
        widget.onDuplicatePage?.call();
      case _NotebookFileAction.deletePage:
        widget.onDeletePage?.call();
    }
  }
}

class _WordPadTitleBar extends StatelessWidget {
  const _WordPadTitleBar({
    required this.title,
    required this.onUndo,
    required this.onRedo,
    required this.onLayers,
  });

  final String title;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onLayers;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5F8),
        border: Border(bottom: BorderSide(color: Color(0xFFD7DAE0))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 17,
            color: Color(0xFF3465A4),
          ),
          const SizedBox(width: 4),
          WordPadCompactIconButton(
            tooltip: 'Desfazer',
            icon: Icons.undo,
            onPressed: onUndo,
          ),
          WordPadCompactIconButton(
            tooltip: 'Refazer',
            icon: Icons.redo,
            onPressed: onRedo,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title — LexPDF',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF25272A),
              ),
            ),
          ),
          WordPadCompactIconButton(
            tooltip: 'Camadas',
            icon: Icons.layers_outlined,
            onPressed: onLayers,
          ),
        ],
      ),
    );
  }
}

class _WordPadTabStrip extends StatelessWidget {
  const _WordPadTabStrip({
    required this.activeTab,
    required this.onTabChanged,
    required this.onFileAction,
    required this.canDeleteNotebook,
    required this.canDuplicatePage,
    required this.canDeletePage,
  });

  final NotebookRibbonTab activeTab;
  final ValueChanged<NotebookRibbonTab> onTabChanged;
  final ValueChanged<_NotebookFileAction> onFileAction;
  final bool canDeleteNotebook;
  final bool canDuplicatePage;
  final bool canDeletePage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(bottom: BorderSide(color: Color(0xFFD7DAE0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopupMenuButton<_NotebookFileAction>(
            tooltip: 'Arquivo',
            position: PopupMenuPosition.under,
            onSelected: onFileAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _NotebookFileAction.openDocument,
                child: _FileMenuLabel(
                  icon: Icons.folder_open_outlined,
                  label: 'Abrir documento',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.saveDocx,
                child: _FileMenuLabel(
                  icon: Icons.save_outlined,
                  label: 'Salvar como DOCX',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.saveTxt,
                child: _FileMenuLabel(
                  icon: Icons.text_snippet_outlined,
                  label: 'Salvar como TXT',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.exportPdf,
                child: _FileMenuLabel(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Exportar PDF',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.saveDoc,
                child: _FileMenuLabel(
                  icon: Icons.description_outlined,
                  label: 'Salvar como DOC',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.saveRtf,
                child: _FileMenuLabel(
                  icon: Icons.description_outlined,
                  label: 'Salvar como RTF',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _NotebookFileAction.newNotebook,
                child: _FileMenuLabel(
                  icon: Icons.note_add_outlined,
                  label: 'Novo caderno',
                ),
              ),
              const PopupMenuItem(
                value: _NotebookFileAction.renameNotebook,
                child: _FileMenuLabel(
                  icon: Icons.drive_file_rename_outline,
                  label: 'Renomear caderno',
                ),
              ),
              PopupMenuItem(
                value: _NotebookFileAction.deleteNotebook,
                enabled: canDeleteNotebook,
                child: const _FileMenuLabel(
                  icon: Icons.delete_outline,
                  label: 'Excluir caderno',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _NotebookFileAction.newPage,
                child: _FileMenuLabel(
                  icon: Icons.post_add_outlined,
                  label: 'Nova página',
                ),
              ),
              PopupMenuItem(
                value: _NotebookFileAction.duplicatePage,
                enabled: canDuplicatePage,
                child: const _FileMenuLabel(
                  icon: Icons.copy_all_outlined,
                  label: 'Duplicar página',
                ),
              ),
              PopupMenuItem(
                value: _NotebookFileAction.deletePage,
                enabled: canDeletePage,
                child: const _FileMenuLabel(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Excluir página',
                ),
              ),
            ],
            child: Container(
              width: 72,
              alignment: Alignment.center,
              color: const Color(0xFF2F66B3),
              child: const Text(
                'Arquivo',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          _RibbonTabButton(
            label: 'Início',
            selected: activeTab == NotebookRibbonTab.home,
            onPressed: () => onTabChanged(NotebookRibbonTab.home),
          ),
          _RibbonTabButton(
            label: 'Desenho',
            selected: activeTab == NotebookRibbonTab.drawing,
            onPressed: () => onTabChanged(NotebookRibbonTab.drawing),
          ),
          _RibbonTabButton(
            label: 'Exibir',
            selected: activeTab == NotebookRibbonTab.view,
            onPressed: () => onTabChanged(NotebookRibbonTab.view),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _RibbonTabButton extends StatelessWidget {
  const _RibbonTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minWidth: 74),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF9FAFC) : Colors.transparent,
          border: selected
              ? const Border(
                  left: BorderSide(color: Color(0xFFD7DAE0)),
                  right: BorderSide(color: Color(0xFFD7DAE0)),
                  top: BorderSide(color: Color(0xFF6B8FBE), width: 2),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? const Color(0xFF1F3656) : const Color(0xFF34373B),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class WordPadRibbonGroup extends StatelessWidget {
  const WordPadRibbonGroup({
    required this.label,
    required this.child,
    this.minWidth,
    super.key,
  });

  final String label;
  final Widget child;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 2),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD5D8DE))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(child: Center(child: child)),
          SizedBox(
            height: 15,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF676B72)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WordPadCompactIconButton extends StatelessWidget {
  const WordPadCompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.size = 27,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        canRequestFocus: onPressed != null,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFDCEAFB) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: selected
                ? Border.all(color: const Color(0xFF8CB3E0))
                : null,
          ),
          child: Icon(
            icon,
            size: 17,
            color: onPressed == null
                ? const Color(0xFFA7AAB0)
                : const Color(0xFF34373B),
          ),
        ),
      ),
    );
  }
}

class WordPadLabeledCommand extends StatelessWidget {
  const WordPadLabeledCommand({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: 54,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCEAFB) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: selected ? Border.all(color: const Color(0xFF8CB3E0)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: onPressed == null
                  ? const Color(0xFFA7AAB0)
                  : const Color(0xFF34373B),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: onPressed == null
                    ? const Color(0xFFA7AAB0)
                    : const Color(0xFF34373B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotebookWordPadViewRibbon extends StatelessWidget {
  const NotebookWordPadViewRibbon({
    required this.showDocumentRuler,
    required this.onShowDocumentRulerChanged,
    required this.onLayers,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onActualSize,
    required this.onFitPage,
    super.key,
  });

  final bool showDocumentRuler;
  final ValueChanged<bool> onShowDocumentRulerChanged;
  final VoidCallback onLayers;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onActualSize;
  final VoidCallback onFitPage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Mostrar',
            minWidth: 150,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: showDocumentRuler,
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) =>
                      onShowDocumentRulerChanged(value ?? true),
                ),
                const Text('Régua', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                WordPadLabeledCommand(
                  label: 'Camadas',
                  icon: Icons.layers_outlined,
                  onPressed: onLayers,
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Zoom',
            minWidth: 250,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Menos',
                  icon: Icons.zoom_out,
                  onPressed: onZoomOut,
                ),
                WordPadLabeledCommand(
                  label: '100%',
                  icon: Icons.filter_1_outlined,
                  onPressed: onActualSize,
                ),
                WordPadLabeledCommand(
                  label: 'Mais',
                  icon: Icons.zoom_in,
                  onPressed: onZoomIn,
                ),
                WordPadLabeledCommand(
                  label: 'Página',
                  icon: Icons.fit_screen_outlined,
                  onPressed: onFitPage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotebookDocumentRuler extends StatelessWidget {
  const NotebookDocumentRuler({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F3F5),
        border: Border(bottom: BorderSide(color: Color(0xFFC9CDD4))),
      ),
      child: const CustomPaint(
        painter: _DocumentRulerPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _DocumentRulerPainter extends CustomPainter {
  const _DocumentRulerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const leftGutter = 42.0;
    const majorStep = 48.0;
    const minorStep = 12.0;
    final linePaint = Paint()
      ..color = const Color(0xFF8B8F96)
      ..strokeWidth = 0.8;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    canvas.drawLine(
      const Offset(leftGutter, 24),
      Offset(size.width, 24),
      linePaint,
    );

    var index = 0;
    for (double x = leftGutter; x <= size.width; x += minorStep) {
      final major = index % 4 == 0;
      final half = index % 2 == 0;
      final tick = major ? 9.0 : (half ? 6.0 : 4.0);
      canvas.drawLine(Offset(x, 24), Offset(x, 24 - tick), linePaint);
      if (major && x > leftGutter) {
        final label = ((x - leftGutter) / majorStep).round().toString();
        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(fontSize: 8.5, color: Color(0xFF5D6167)),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, 2));
      }
      index++;
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentRulerPainter oldDelegate) => false;
}

class NotebookWordPadStatusBar extends StatelessWidget {
  const NotebookWordPadStatusBar({
    required this.pageIndex,
    required this.pageCount,
    required this.wordCount,
    required this.layerName,
    required this.zoom,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onZoomChanged,
    required this.onFitPage,
    super.key,
  });

  final int pageIndex;
  final int pageCount;
  final int wordCount;
  final String layerName;
  final double zoom;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onFitPage;

  @override
  Widget build(BuildContext context) {
    final percent = (zoom * 100).round();
    return Container(
      height: 29,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F3F5),
        border: Border(top: BorderSide(color: Color(0xFFC8CBD1))),
      ),
      child: Row(
        children: [
          WordPadCompactIconButton(
            tooltip: 'Página anterior',
            icon: Icons.chevron_left,
            onPressed: onPreviousPage,
            size: 23,
          ),
          Text(
            'Página ${pageIndex + 1} de $pageCount',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF44484E)),
          ),
          WordPadCompactIconButton(
            tooltip: 'Próxima página',
            icon: Icons.chevron_right,
            onPressed: onNextPage,
            size: 23,
          ),
          const _StatusSeparator(),
          Text(
            'Palavras: $wordCount',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF44484E)),
          ),
          const _StatusSeparator(),
          Flexible(
            child: Text(
              'Camada: $layerName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF44484E)),
            ),
          ),
          const Spacer(),
          WordPadCompactIconButton(
            tooltip: 'Ajustar à página',
            icon: Icons.fit_screen_outlined,
            onPressed: onFitPage,
            size: 23,
          ),
          Text('$percent%', style: const TextStyle(fontSize: 10.5)),
          const SizedBox(width: 4),
          const Icon(Icons.remove, size: 13),
          SizedBox(
            width: 118,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
              ),
              child: Slider(
                min: 0.25,
                max: 4,
                value: zoom.clamp(0.25, 4).toDouble(),
                onChanged: onZoomChanged,
              ),
            ),
          ),
          const Icon(Icons.add, size: 13),
        ],
      ),
    );
  }
}

class _StatusSeparator extends StatelessWidget {
  const _StatusSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 9),
      color: const Color(0xFFD0D3D8),
    );
  }
}

class _FileMenuLabel extends StatelessWidget {
  const _FileMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

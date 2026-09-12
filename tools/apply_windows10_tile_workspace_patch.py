from pathlib import Path

path = Path('apps/lexpdf_app/lib/src/screens/pdf_workspace_stylus_screen.dart')
source = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one occurrence, found {count}: {old[:80]!r}')
    source = source.replace(old, new, 1)


if "../widgets/windows10_pdf_tile_overlay.dart" not in source:
    replace_once(
        "import '../widgets/pdf_stylus_page_overlay.dart';\n",
        "import '../widgets/pdf_stylus_page_overlay.dart';\n"
        "import '../widgets/windows10_pdf_tile_overlay.dart';\n",
    )

if 'bool get _windows10Tiles =>' not in source:
    replace_once(
        "  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;\n",
        "  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;\n\n"
        "  bool get _windows10Tiles => isWindows10ManualTileRenderingEnabled();\n",
    )

if 'onePassRenderingSizeThreshold: _windows10Tiles' not in source:
    replace_once(
        "                          onePassRenderingSizeThreshold: _windows ? 6000 : 1400,\n",
        "                          onePassRenderingSizeThreshold: _windows10Tiles\n"
        "                              ? 1000\n"
        "                              : (_windows ? 6000 : 1400),\n",
    )

if 'if (_windows10Tiles) return 1.0;' not in source:
    replace_once(
        "                              ? (context, page, controller, estimatedScale) {\n"
        "                                  const maxRenderPixels = 6000.0;\n",
        "                              ? (context, page, controller, estimatedScale) {\n"
        "                                  // The Win10 manual tile layer supplies the visible\n"
        "                                  // page pixels. Keep pdfrx's hidden backing page at\n"
        "                                  // 72 dpi so it never allocates the giant bitmap\n"
        "                                  // path that corrupts on affected Windows 10 PCs.\n"
        "                                  if (_windows10Tiles) return 1.0;\n"
        "                                  const maxRenderPixels = 6000.0;\n",
    )

if 'pagePaintCallbacks: _windows10Tiles' not in source:
    replace_once(
        "                          pagePaintCallbacks: [_selectionMenu.paint],\n",
        "                          pagePaintCallbacks: _windows10Tiles\n"
        "                              ? const []\n"
        "                              : [_selectionMenu.paint],\n",
    )

if 'Windows10PdfTileOverlay(' not in source:
    replace_once(
        "                          pageOverlaysBuilder: (context, pageRect, page) => [\n"
        "                            Positioned.fill(\n"
        "                              child: PdfStylusPageOverlay(\n",
        "                          pageOverlaysBuilder: (context, pageRect, page) => [\n"
        "                            if (_windows10Tiles)\n"
        "                              Positioned.fill(\n"
        "                                child: Windows10PdfTileOverlay(\n"
        "                                  key: ValueKey(\n"
        "                                    'win10-tiles-${page.pageNumber}',\n"
        "                                  ),\n"
        "                                  page: page,\n"
        "                                  pageRect: pageRect,\n"
        "                                  controller: _controller,\n"
        "                                ),\n"
        "                              ),\n"
        "                            if (_windows10Tiles)\n"
        "                              Positioned.fill(\n"
        "                                child: IgnorePointer(\n"
        "                                  child: CustomPaint(\n"
        "                                    painter: _SelectionMarkupOverlayPainter(\n"
        "                                      menu: _selectionMenu,\n"
        "                                      pageRect: pageRect,\n"
        "                                      page: page,\n"
        "                                    ),\n"
        "                                  ),\n"
        "                                ),\n"
        "                              ),\n"
        "                            Positioned.fill(\n"
        "                              child: PdfStylusPageOverlay(\n",
    )

if 'class _SelectionMarkupOverlayPainter extends CustomPainter' not in source:
    replace_once(
        "class _CommandButton extends StatelessWidget {\n",
        "class _SelectionMarkupOverlayPainter extends CustomPainter {\n"
        "  const _SelectionMarkupOverlayPainter({\n"
        "    required this.menu,\n"
        "    required this.pageRect,\n"
        "    required this.page,\n"
        "  });\n\n"
        "  final PdfSelectionActionMenu menu;\n"
        "  final Rect pageRect;\n"
        "  final PdfPage page;\n\n"
        "  @override\n"
        "  void paint(Canvas canvas, Size size) {\n"
        "    canvas.save();\n"
        "    canvas.translate(-pageRect.left, -pageRect.top);\n"
        "    menu.paint(canvas, pageRect, page);\n"
        "    canvas.restore();\n"
        "  }\n\n"
        "  @override\n"
        "  bool shouldRepaint(covariant _SelectionMarkupOverlayPainter oldDelegate) => true;\n"
        "}\n\n"
        "class _CommandButton extends StatelessWidget {\n",
    )

path.write_text(source, encoding='utf-8')

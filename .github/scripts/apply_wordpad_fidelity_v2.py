from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCREEN = ROOT / "apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart"
DATABASE = ROOT / "apps/lexpdf_app/lib/src/core/storage/local_database.dart"
OBJECT_LAYER = ROOT / "apps/lexpdf_app/lib/src/widgets/notebook_object_layer.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"{label}: start marker not found")
    end_index = text.find(end, start_index + len(start))
    if end_index < 0:
        raise RuntimeError(f"{label}: end marker not found")
    return text[:start_index] + replacement + text[end_index:]


def patch_database() -> None:
    text = DATABASE.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "static const int schemaVersion = 9;",
        "static const int schemaVersion = 10;",
        "schema version",
    )
    marker = "\n  void close() => database.dispose();\n}"
    migration = """

    if (version < 10) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute(
          \"ALTER TABLE notebook_objects ADD COLUMN text_align TEXT NOT NULL DEFAULT 'left' CHECK(text_align IN ('left', 'center', 'right', 'justify'));\",
        );
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', [
          '10',
          'schema_version',
        ]);
        database.userVersion = 10;
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
"""
    text = replace_once(text, marker, migration + marker, "schema v10 migration")
    DATABASE.write_text(text, encoding="utf-8")


def patch_object_layer() -> None:
    text = OBJECT_LAYER.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "enum _ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }\n",
        """enum _ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

TextAlign _notebookFlutterTextAlign(NotebookTextAlign value) => switch (value) {
      NotebookTextAlign.left => TextAlign.left,
      NotebookTextAlign.center => TextAlign.center,
      NotebookTextAlign.right => TextAlign.right,
      NotebookTextAlign.justify => TextAlign.justify,
    };
""",
        "text alignment mapper",
    )
    start = "    if (object.type == NotebookObjectType.text) {\n"
    end = "    if (object.type == NotebookObjectType.image) {\n"
    replacement = """    if (object.type == NotebookObjectType.text) {
      return SizedBox.expand(
        child: Text(
          object.textValue ?? '',
          maxLines: null,
          textAlign: _notebookFlutterTextAlign(object.textAlign),
          style: TextStyle(
            color: Color(object.colorValue),
            fontSize: object.fontSize ?? 12,
            fontFamily: object.fontFamily ?? 'Arial',
            fontWeight: object.fontBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: object.fontItalic ? FontStyle.italic : FontStyle.normal,
            decoration: object.fontUnderline ? TextDecoration.underline : null,
          ),
        ),
      );
    }
"""
    text = replace_between(text, start, end, replacement, "rendered text alignment")
    text = replace_once(
        text,
        "      keyboardType: TextInputType.multiline,\n      textAlignVertical: TextAlignVertical.top,",
        "      keyboardType: TextInputType.multiline,\n      textAlign: _notebookFlutterTextAlign(widget.object.textAlign),\n      textAlignVertical: TextAlignVertical.top,",
        "inline editor alignment",
    )
    OBJECT_LAYER.write_text(text, encoding="utf-8")


def patch_screen() -> None:
    text = SCREEN.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import '../widgets/notebook_ruler_overlay.dart';\n",
        "import '../widgets/notebook_ruler_overlay.dart';\nimport '../widgets/notebook_wordpad_chrome.dart';\n",
        "WordPad chrome import",
    )
    text = replace_once(
        text,
        "  bool _rulerMode = false;\n  double _zoom = 1.0;",
        "  bool _rulerMode = false;\n  bool _showDocumentRuler = true;\n  double _zoom = 1.0;",
        "document ruler state",
    )
    text = replace_once(
        text,
        "  bool _defaultTextUnderline = false;\n  int _defaultTextColorValue = 0xFF000000;",
        "  bool _defaultTextUnderline = false;\n  NotebookTextAlign _defaultTextAlign = NotebookTextAlign.left;\n  int _defaultTextColorValue = 0xFF000000;",
        "default text alignment",
    )

    build_start = "  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n"
    build_end = "  Widget _buildPageViewport(InkNotebookPage page) {\n"
    new_build = """  int get _wordCount {
    final combined = _allObjects
        .where((object) => object.type == NotebookObjectType.text)
        .map((object) => object.textValue ?? '')
        .join(' ')
        .trim();
    if (combined.isEmpty) return 0;
    return RegExp(r'\\S+').allMatches(combined).length;
  }

  Widget _buildViewRibbon() {
    return NotebookWordPadViewRibbon(
      showDocumentRuler: _showDocumentRuler,
      onShowDocumentRulerChanged: (value) =>
          setState(() => _showDocumentRuler = value),
      onLayers: () => unawaited(_showLayers()),
      onZoomOut: () => _zoomBy(0.85),
      onZoomIn: () => _zoomBy(1.15),
      onActualSize: () => _setZoom(1),
      onFitPage: _resetZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Não foi possível abrir o caderno: ${snapshot.error}',
              ),
            );
          }
          final page = _currentPage;
          if (page == null) {
            return const Center(child: Text('Nenhuma página disponível.'));
          }
          final pageIndex = _pageIndex;
          return NotebookWordPadScaffold(
            title: _currentNotebook?.title ?? 'Cadernos',
            homeRibbon: _buildTextFormattingToolbar(),
            drawingRibbon: _buildToolbar(),
            viewRibbon: _buildViewRibbon(),
            document: _buildPageViewport(page),
            pageIndex: pageIndex < 0 ? 0 : pageIndex,
            pageCount: _pages.length,
            wordCount: _wordCount,
            layerName: _activeLayer?.name ?? 'Camada 1',
            zoom: _zoom,
            showDocumentRuler: _showDocumentRuler,
            onNewNotebook: () => unawaited(_createNotebook()),
            onRenameNotebook: () => unawaited(_renameNotebook()),
            onDeleteNotebook: _notebooks.length > 1
                ? () => unawaited(_deleteNotebook())
                : null,
            onNewPage: () => unawaited(_addPage()),
            onDuplicatePage: () => unawaited(_duplicatePage()),
            onDeletePage: _pages.length > 1
                ? () => unawaited(_deletePage())
                : null,
            onLayers: () => unawaited(_showLayers()),
            onPreviousPage: pageIndex > 0
                ? () => unawaited(_openPageAt(pageIndex - 1))
                : null,
            onNextPage: pageIndex >= 0 && pageIndex < _pages.length - 1
                ? () => unawaited(_openPageAt(pageIndex + 1))
                : null,
            onUndo: _history.canUndo ? () => unawaited(_undoHistory()) : null,
            onRedo: _history.canRedo ? () => unawaited(_redoHistory()) : null,
            onZoomChanged: _setZoom,
            onFitPage: _resetZoom,
          );
        },
      ),
    );
  }

"""
    text = replace_between(text, build_start, build_end, new_build, "screen shell")

    text = replace_once(
        text,
        "      color: Theme.of(context).colorScheme.surfaceContainerLowest,",
        "      color: const Color(0xFFD9DDE2),",
        "desktop canvas background",
    )
    text = replace_once(
        text,
        "                      borderRadius: BorderRadius.circular(4),\n                      boxShadow: const [\n                        BoxShadow(blurRadius: 12, color: Color(0x22000000)),\n                      ],",
        "                      borderRadius: BorderRadius.circular(1),\n                      border: Border.all(color: const Color(0xFFC6C9CE)),\n                      boxShadow: const [\n                        BoxShadow(\n                          blurRadius: 5,\n                          offset: Offset(0, 2),\n                          color: Color(0x26000000),\n                        ),\n                      ],",
        "paper styling",
    )

    zoom_overlay = re.compile(
        r"\n          Positioned\(\n            right: 16,\n            bottom: 16,\n            child: NotebookZoomControls\(.*?\n            \),\n          \),",
        re.S,
    )
    text, count = zoom_overlay.subn("", text, count=1)
    if count != 1:
        raise RuntimeError(f"zoom overlay: expected exactly one match, got {count}")

    text = replace_once(
        text,
        "    int? colorValue,\n  }) {",
        "    int? colorValue,\n    NotebookTextAlign? textAlign,\n  }) {",
        "text style signature",
    )
    text = replace_once(
        text,
        "        if (underline != null) _defaultTextUnderline = underline;\n        if (fontSize != null)",
        "        if (underline != null) _defaultTextUnderline = underline;\n        if (textAlign != null) _defaultTextAlign = textAlign;\n        if (fontSize != null)",
        "default alignment style",
    )
    text = replace_once(
        text,
        "        fontUnderline: underline,\n        fontSize: fontSize,",
        "        fontUnderline: underline,\n        textAlign: textAlign,\n        fontSize: fontSize,",
        "object alignment style",
    )
    text = replace_once(
        text,
        "      fontUnderline: _defaultTextUnderline,\n      createdAt: now,",
        "      fontUnderline: _defaultTextUnderline,\n      textAlign: _defaultTextAlign,\n      createdAt: now,",
        "new text alignment",
    )

    toolbar_start = "  Widget _buildTextFormattingToolbar() {\n"
    toolbar_end = "  Future<void> _recognizeSelectedInk() async {\n"
    toolbar = """  Widget _buildTextFormattingToolbar() {
    final selected = _selectedObject;
    final object = selected?.type == NotebookObjectType.text ? selected : null;
    const fontSizes = <double>[10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48];
    const fonts = <String, String>{
      'Arial': 'Arial',
      'Roboto': 'Roboto',
      'Serif': 'serif',
      'Monoespaçada': 'monospace',
    };
    final currentFamily = object?.fontFamily ?? _defaultTextFontFamily;
    final currentSize = object?.fontSize ?? _defaultTextFontSize;
    final currentBold = object?.fontBold ?? _defaultTextBold;
    final currentItalic = object?.fontItalic ?? _defaultTextItalic;
    final currentUnderline = object?.fontUnderline ?? _defaultTextUnderline;
    final currentAlign = object?.textAlign ?? _defaultTextAlign;
    final currentColor = object?.colorValue ?? _defaultTextColorValue;

    Widget alignButton(
      String tooltip,
      IconData icon,
      NotebookTextAlign alignment,
    ) {
      return WordPadCompactIconButton(
        tooltip: tooltip,
        icon: icon,
        selected: currentAlign == alignment,
        onPressed: _canEditActiveLayer
            ? () => _setSelectedTextStyle(textAlign: alignment)
            : null,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Fonte',
            minWidth: 265,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 136,
                      height: 27,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: fonts.containsValue(currentFamily)
                              ? currentFamily
                              : _defaultNotebookFontFamily,
                          isDense: true,
                          isExpanded: true,
                          items: fonts.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.value,
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _canEditActiveLayer
                              ? (family) {
                                  if (family != null) {
                                    _setSelectedTextStyle(fontFamily: family);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 48,
                      height: 27,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: fontSizes.contains(currentSize)
                              ? currentSize
                              : _defaultNotebookFontSize,
                          isDense: true,
                          isExpanded: true,
                          items: fontSizes
                              .map(
                                (size) => DropdownMenuItem(
                                  value: size,
                                  child: Text(
                                    size.toInt().toString(),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _canEditActiveLayer
                              ? (size) {
                                  if (size != null) {
                                    _setSelectedTextStyle(fontSize: size);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Aumentar fonte',
                      icon: Icons.text_increase,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                                fontSize: (currentSize + 2).clamp(8, 72).toDouble(),
                              )
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Diminuir fonte',
                      icon: Icons.text_decrease,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                                fontSize: (currentSize - 2).clamp(8, 72).toDouble(),
                              )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordPadCompactIconButton(
                      tooltip: 'Negrito',
                      icon: Icons.format_bold,
                      selected: currentBold,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(bold: !currentBold)
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Itálico',
                      icon: Icons.format_italic,
                      selected: currentItalic,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(italic: !currentItalic)
                          : null,
                    ),
                    WordPadCompactIconButton(
                      tooltip: 'Sublinhado',
                      icon: Icons.format_underline,
                      selected: currentUnderline,
                      onPressed: _canEditActiveLayer
                          ? () => _setSelectedTextStyle(
                                underline: !currentUnderline,
                              )
                          : null,
                    ),
                    PopupMenuButton<int>(
                      tooltip: 'Cor da fonte',
                      onSelected: (value) =>
                          _setSelectedTextStyle(colorValue: value),
                      itemBuilder: (_) => _palette
                          .map(
                            (value) => PopupMenuItem<int>(
                              value: value,
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    color: Color(value),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value == currentColor
                                        ? 'Cor selecionada'
                                        : 'Usar cor',
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      child: SizedBox(
                        width: 32,
                        height: 27,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.format_color_text, size: 17),
                            Positioned(
                              left: 5,
                              right: 5,
                              bottom: 2,
                              child: Container(height: 3, color: Color(currentColor)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Parágrafo',
            minWidth: 135,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                alignButton('Alinhar à esquerda', Icons.format_align_left, NotebookTextAlign.left),
                alignButton('Centralizar', Icons.format_align_center, NotebookTextAlign.center),
                alignButton('Alinhar à direita', Icons.format_align_right, NotebookTextAlign.right),
                alignButton('Justificar', Icons.format_align_justify, NotebookTextAlign.justify),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Inserir',
            minWidth: 220,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: object == null ? 'Texto' : 'Editar',
                  icon: Icons.text_fields,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(_addText())
                      : null,
                ),
                WordPadLabeledCommand(
                  label: 'Imagem',
                  icon: Icons.image_outlined,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(_addImage())
                      : null,
                ),
                WordPadLabeledCommand(
                  label: 'Página',
                  icon: Icons.note_add_outlined,
                  onPressed: () => unawaited(_addPage()),
                ),
                WordPadLabeledCommand(
                  label: 'Objeto',
                  icon: Icons.crop_square_outlined,
                  onPressed: _canEditActiveLayer
                      ? () => unawaited(_addShape(NotebookObjectType.rectangle))
                      : null,
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Edição',
            minWidth: 125,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WordPadLabeledCommand(
                  label: 'Desfazer',
                  icon: Icons.undo,
                  onPressed: _history.canUndo
                      ? () => unawaited(_undoHistory())
                      : null,
                ),
                WordPadLabeledCommand(
                  label: 'Refazer',
                  icon: Icons.redo,
                  onPressed: _history.canRedo
                      ? () => unawaited(_redoHistory())
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

"""
    text = replace_between(text, toolbar_start, toolbar_end, toolbar, "home ribbon")

    text = text.replace(
        "  Widget _buildLayerStatus() {\n",
        "  // Kept for the legacy compact navigation path.\n  // ignore: unused_element\n  Widget _buildLayerStatus() {\n",
        1,
    )
    text = text.replace(
        "  Widget _buildNotebookNavigation() {\n",
        "  // Kept for compatibility with the previous notebook chrome.\n  // ignore: unused_element\n  Widget _buildNotebookNavigation() {\n",
        1,
    )
    text = text.replace(
        "  Future<void> _showCustomZoomDialog() async {\n",
        "  // Retained for callers that may reintroduce a custom zoom command.\n  // ignore: unused_element\n  Future<void> _showCustomZoomDialog() async {\n",
        1,
    )

    SCREEN.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    patch_database()
    patch_object_layer()
    patch_screen()
    print("WordPad fidelity v2 production patch applied.")

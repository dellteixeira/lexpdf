from pathlib import Path

root = Path('apps/lexpdf_app')

# ---------- model ----------
model_path = root / 'lib/src/core/notebook/notebook_object_models.dart'
model = model_path.read_text()
model = model.replace(
"""}\n\n@immutable\nclass NotebookObject {\n""",
"""}\n\nenum NotebookTextAlign {\n  left,\n  center,\n  right,\n  justify;\n\n  String get dbValue => name;\n\n  TextAlign get flutterValue => switch (this) {\n    NotebookTextAlign.left => TextAlign.left,\n    NotebookTextAlign.center => TextAlign.center,\n    NotebookTextAlign.right => TextAlign.right,\n    NotebookTextAlign.justify => TextAlign.justify,\n  };\n\n  static NotebookTextAlign fromDb(String? value) => switch (value) {\n    'center' => NotebookTextAlign.center,\n    'right' => NotebookTextAlign.right,\n    'justify' => NotebookTextAlign.justify,\n    _ => NotebookTextAlign.left,\n  };\n}\n\n@immutable\nclass NotebookObject {\n""",
)
model = model.replace(
"""import 'package:flutter/foundation.dart';\n""",
"""import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart' show TextAlign;\n""",
)
model = model.replace(
"""    this.fontUnderline = false,\n    this.imagePath,\n""",
"""    this.fontUnderline = false,\n    this.textAlign = NotebookTextAlign.left,\n    this.imagePath,\n""",
)
model = model.replace(
"""  final bool fontUnderline;\n  final String? imagePath;\n""",
"""  final bool fontUnderline;\n  final NotebookTextAlign textAlign;\n  final String? imagePath;\n""",
)
model = model.replace(
"""    bool? fontUnderline,\n    String? imagePath,\n""",
"""    bool? fontUnderline,\n    NotebookTextAlign? textAlign,\n    String? imagePath,\n""",
)
model = model.replace(
"""      fontUnderline: fontUnderline ?? this.fontUnderline,\n      imagePath: imagePath ?? this.imagePath,\n""",
"""      fontUnderline: fontUnderline ?? this.fontUnderline,\n      textAlign: textAlign ?? this.textAlign,\n      imagePath: imagePath ?? this.imagePath,\n""",
)
model_path.write_text(model)

# ---------- store ----------
store_path = root / 'lib/src/core/storage/local_notebook_object_store.dart'
store = store_path.read_text()
store = store.replace(
"""        font_bold, font_italic, font_underline, image_path, created_at, updated_at\n      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);\n""",
"""        font_bold, font_italic, font_underline, text_align, image_path, created_at, updated_at\n      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);\n""",
)
store = store.replace(
"""        object.fontUnderline ? 1 : 0,\n        object.imagePath,\n""",
"""        object.fontUnderline ? 1 : 0,\n        object.textAlign.dbValue,\n        object.imagePath,\n""",
)
store = store.replace(
"""        fontUnderline: object.fontUnderline,\n        imagePath: object.imagePath,\n""",
"""        fontUnderline: object.fontUnderline,\n        textAlign: object.textAlign,\n        imagePath: object.imagePath,\n""",
)
store = store.replace(
"""    fontUnderline: (row['font_underline'] as int? ?? 0) != 0,\n    imagePath: row['image_path'] as String?,\n""",
"""    fontUnderline: (row['font_underline'] as int? ?? 0) != 0,\n    textAlign: NotebookTextAlign.fromDb(row['text_align'] as String?),\n    imagePath: row['image_path'] as String?,\n""",
)
store_path.write_text(store)

# ---------- database ----------
db_path = root / 'lib/src/core/storage/local_database.dart'
db = db_path.read_text()
db = db.replace('static const int schemaVersion = 9;', 'static const int schemaVersion = 10;')
needle = """    if (version < 9) {\n      database.execute('BEGIN IMMEDIATE;');\n      try {\n        database.execute(\n          'ALTER TABLE notebook_objects ADD COLUMN font_family TEXT;',\n        );\n        database.execute(\n          'ALTER TABLE notebook_objects ADD COLUMN font_bold INTEGER NOT NULL DEFAULT 0 CHECK(font_bold IN (0, 1));',\n        );\n        database.execute(\n          'ALTER TABLE notebook_objects ADD COLUMN font_italic INTEGER NOT NULL DEFAULT 0 CHECK(font_italic IN (0, 1));',\n        );\n        database.execute(\n          'ALTER TABLE notebook_objects ADD COLUMN font_underline INTEGER NOT NULL DEFAULT 0 CHECK(font_underline IN (0, 1));',\n        );\n        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', [\n          '9',\n          'schema_version',\n        ]);\n        database.userVersion = 9;\n        database.execute('COMMIT;');\n      } catch (_) {\n        database.execute('ROLLBACK;');\n        rethrow;\n      }\n    }\n"""
if needle not in db:
    raise SystemExit('schema v9 migration block not found')
replacement = needle + """\n    if (version < 10) {\n      database.execute('BEGIN IMMEDIATE;');\n      try {\n        database.execute(\n          \"ALTER TABLE notebook_objects ADD COLUMN text_align TEXT NOT NULL DEFAULT 'left' CHECK(text_align IN ('left', 'center', 'right', 'justify'));\",\n        );\n        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', [\n          '10',\n          'schema_version',\n        ]);\n        database.userVersion = 10;\n        database.execute('COMMIT;');\n      } catch (_) {\n        database.execute('ROLLBACK;');\n        rethrow;\n      }\n    }\n"""
db = db.replace(needle, replacement)
db_path.write_text(db)

# ---------- object layer ----------
layer_path = root / 'lib/src/widgets/notebook_object_layer.dart'
layer = layer_path.read_text()
layer = layer.replace(
"""          maxLines: null,\n          style: TextStyle(\n""",
"""          maxLines: null,\n          textAlign: object.textAlign.flutterValue,\n          style: TextStyle(\n""",
1,
)
layer = layer.replace(
"""      textAlignVertical: TextAlignVertical.top,\n      style: _style,\n""",
"""      textAlignVertical: TextAlignVertical.top,\n      textAlign: widget.object.textAlign.flutterValue,\n      style: _style,\n""",
1,
)
layer = layer.replace(
"""    fontFamily: widget.object.fontFamily ?? 'Arial',\n""",
"""    fontFamily: widget.object.fontFamily ?? 'Arial',\n    fontFamilyFallback: const ['Liberation Sans', 'Roboto', 'sans-serif'],\n""",
1,
)
layer = layer.replace(
"""            fontFamily: object.fontFamily ?? 'Arial',\n""",
"""            fontFamily: object.fontFamily ?? 'Arial',\n            fontFamilyFallback: const ['Liberation Sans', 'Roboto', 'sans-serif'],\n""",
1,
)
layer_path.write_text(layer)

# ---------- screen ----------
screen_path = root / 'lib/src/screens/layered_notebook_screen.dart'
screen = screen_path.read_text()
screen = screen.replace(
"""import '../widgets/notebook_ruler_overlay.dart';\n""",
"""import '../widgets/notebook_ruler_overlay.dart';\nimport '../widgets/notebook_wordpad_chrome.dart';\n""",
)
screen = screen.replace(
"""  String? _editingTextObjectId;\n  String _defaultTextFontFamily = _defaultNotebookFontFamily;\n""",
"""  String? _editingTextObjectId;\n  NotebookRibbonTab _ribbonTab = NotebookRibbonTab.home;\n  bool _documentRulerVisible = true;\n  String _defaultTextFontFamily = _defaultNotebookFontFamily;\n""",
)
screen = screen.replace(
"""  int _defaultTextColorValue = 0xFF000000;\n  bool _suppressMutationHistory = false;\n""",
"""  int _defaultTextColorValue = 0xFF000000;\n  NotebookTextAlign _defaultTextAlign = NotebookTextAlign.left;\n  bool _suppressMutationHistory = false;\n""",
)

build_start = screen.index('  @override\n  Widget build(BuildContext context) {')
build_end = screen.index('\n  Widget _buildPageViewport(InkNotebookPage page) {', build_start)
new_build = r'''  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: desktop ? 44 : null,
        titleSpacing: desktop ? 12 : null,
        title: Text('${_currentNotebook?.title ?? 'Caderno'} - LexPDF'),
        actions: [
          if (desktop)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Center(child: Icon(Icons.cloud_done_outlined, size: 18)),
            ),
          IconButton(
            tooltip: 'Desfazer',
            onPressed: _history.canUndo ? _undoHistory : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Refazer',
            onPressed: _history.canRedo ? _redoHistory : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Camadas',
            onPressed: _currentPage == null ? null : _showLayers,
            icon: const Icon(Icons.layers_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opções do caderno',
            onSelected: (value) {
              if (value == 'new') unawaited(_createNotebook());
              if (value == 'rename') unawaited(_renameNotebook());
              if (value == 'delete') unawaited(_deleteNotebook());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'new', child: Text('Novo caderno')),
              PopupMenuItem(value: 'rename', child: Text('Renomear caderno')),
              PopupMenuItem(value: 'delete', child: Text('Excluir caderno')),
            ],
          ),
        ],
      ),
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
          return Column(
            children: [
              NotebookWordPadRibbon(
                activeTab: _ribbonTab,
                onTabChanged: (value) => setState(() => _ribbonTab = value),
                onFilePressed: _showWordPadFileMenu,
                home: _buildWordPadHomeRibbon(),
                drawing: Align(alignment: Alignment.topLeft, child: _buildToolbar()),
                view: _buildWordPadViewRibbon(),
              ),
              _buildNotebookNavigation(),
              NotebookWordPadRuler(visible: _documentRulerVisible),
              Expanded(child: _buildPageViewport(page)),
              NotebookWordPadStatusBar(
                pageIndex: math.max(0, _pageIndex),
                pageCount: _pages.length,
                zoom: _zoom,
                onZoomChanged: _setZoom,
                onZoomOut: () => _zoomBy(0.85),
                onZoomIn: () => _zoomBy(1.15),
                onResetZoom: _resetZoom,
              ),
            ],
          );
        },
      ),
    );
  }
'''
screen = screen[:build_start] + new_build + screen[build_end:]

# cleaner neutral WordPad workspace
screen = screen.replace(
"""      color: Theme.of(context).colorScheme.surfaceContainerLowest,\n""",
"""      color: Theme.of(context).colorScheme.surfaceContainerHigh,\n""",
1,
)

# remove floating pointer helper and floating zoom; status bar owns zoom now
page_start = screen.index('  Widget _buildPageViewport(InkNotebookPage page) {')
floating_start = screen.index('          if (_pointerMode)\n            Positioned(', page_start)
floating_end = screen.index('\n        ],\n      ),\n    );\n  }\n\n  void _zoomBy', floating_start)
screen = screen[:floating_start] + screen[floating_end:]

# text defaults include paragraph alignment
screen = screen.replace(
"""      fontUnderline: _defaultTextUnderline,\n      createdAt: now,\n""",
"""      fontUnderline: _defaultTextUnderline,\n      textAlign: _defaultTextAlign,\n      createdAt: now,\n""",
1,
)

# replace old formatting strip with WordPad-like grouped ribbon
old_toolbar_start = screen.index('  Widget _buildTextFormattingToolbar() {')
old_toolbar_end = screen.index('\n  Future<void> _recognizeSelectedInk()', old_toolbar_start)
new_toolbar = r'''  void _setSelectedTextAlignment(NotebookTextAlign alignment) {
    final object = _selectedObject;
    if (object == null || object.type != NotebookObjectType.text) {
      setState(() => _defaultTextAlign = alignment);
      return;
    }
    _onObjectChanged(
      object.copyWith(
        textAlign: alignment,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Widget _buildWordPadHomeRibbon() {
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
    final currentColor = object?.colorValue ?? _defaultTextColorValue;
    final currentAlign = object?.textAlign ?? _defaultTextAlign;
    final compact = MediaQuery.sizeOf(context).width < 720;

    Widget formatButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
      bool selected = false,
    }) {
      return IconButton(
        tooltip: tooltip,
        isSelected: selected,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 20 : 22),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Fonte',
            minWidth: compact ? 246 : 300,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: compact ? 126 : 154,
                      height: 36,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('wordpad-font-$currentFamily'),
                        initialValue: fonts.containsValue(currentFamily)
                            ? currentFamily
                            : _defaultNotebookFontFamily,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        ),
                        items: fonts.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.value,
                                  child: Text(entry.key),
                                ))
                            .toList(growable: false),
                        onChanged: (family) {
                          if (family != null) {
                            _setSelectedTextStyle(fontFamily: family);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 66,
                      height: 36,
                      child: DropdownButtonFormField<double>(
                        key: ValueKey('wordpad-size-$currentSize'),
                        initialValue: fontSizes.contains(currentSize)
                            ? currentSize
                            : _defaultNotebookFontSize,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                        ),
                        items: fontSizes
                            .map((size) => DropdownMenuItem(
                                  value: size,
                                  child: Text(size.toInt().toString()),
                                ))
                            .toList(growable: false),
                        onChanged: (size) {
                          if (size != null) _setSelectedTextStyle(fontSize: size);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    formatButton(
                      tooltip: 'Negrito',
                      icon: Icons.format_bold,
                      selected: currentBold,
                      onPressed: () => _setSelectedTextStyle(bold: !currentBold),
                    ),
                    formatButton(
                      tooltip: 'Itálico',
                      icon: Icons.format_italic,
                      selected: currentItalic,
                      onPressed: () => _setSelectedTextStyle(italic: !currentItalic),
                    ),
                    formatButton(
                      tooltip: 'Sublinhado',
                      icon: Icons.format_underline,
                      selected: currentUnderline,
                      onPressed: () => _setSelectedTextStyle(underline: !currentUnderline),
                    ),
                    PopupMenuButton<int>(
                      tooltip: 'Cor da fonte',
                      padding: EdgeInsets.zero,
                      icon: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          const Icon(Icons.format_color_text),
                          Container(width: 22, height: 3, color: Color(currentColor)),
                        ],
                      ),
                      itemBuilder: (_) => _palette
                          .map((value) => PopupMenuItem<int>(
                                value: value,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Color(value),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black26),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Text(value == currentColor ? 'Selecionada' : 'Usar cor'),
                                  ],
                                ),
                              ))
                          .toList(growable: false),
                      onSelected: (value) => _setSelectedTextStyle(colorValue: value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Parágrafo',
            minWidth: compact ? 168 : 190,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 1,
              children: [
                formatButton(
                  tooltip: 'Alinhar à esquerda',
                  icon: Icons.format_align_left,
                  selected: currentAlign == NotebookTextAlign.left,
                  onPressed: () => _setSelectedTextAlignment(NotebookTextAlign.left),
                ),
                formatButton(
                  tooltip: 'Centralizar',
                  icon: Icons.format_align_center,
                  selected: currentAlign == NotebookTextAlign.center,
                  onPressed: () => _setSelectedTextAlignment(NotebookTextAlign.center),
                ),
                formatButton(
                  tooltip: 'Alinhar à direita',
                  icon: Icons.format_align_right,
                  selected: currentAlign == NotebookTextAlign.right,
                  onPressed: () => _setSelectedTextAlignment(NotebookTextAlign.right),
                ),
                formatButton(
                  tooltip: 'Justificar',
                  icon: Icons.format_align_justify,
                  selected: currentAlign == NotebookTextAlign.justify,
                  onPressed: () => _setSelectedTextAlignment(NotebookTextAlign.justify),
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Inserir',
            minWidth: compact ? 154 : 190,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WordPadLargeAction(
                  icon: Icons.image_outlined,
                  label: 'Imagem',
                  onPressed: _canEditActiveLayer ? () => unawaited(_addImage()) : null,
                ),
                PopupMenuButton<NotebookObjectType>(
                  tooltip: 'Inserir forma',
                  onSelected: (type) => unawaited(_addShape(type)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: NotebookObjectType.line, child: Text('Linha')),
                    PopupMenuItem(value: NotebookObjectType.arrow, child: Text('Seta')),
                    PopupMenuItem(value: NotebookObjectType.rectangle, child: Text('Retângulo')),
                    PopupMenuItem(value: NotebookObjectType.ellipse, child: Text('Elipse')),
                    PopupMenuItem(value: NotebookObjectType.triangle, child: Text('Triângulo')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined, size: 28),
                        SizedBox(height: 3),
                        Text('Forma', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Edição',
            minWidth: compact ? 142 : 170,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WordPadLargeAction(
                  icon: Icons.edit_note,
                  label: 'Escrever',
                  onPressed: _canEditActiveLayer ? () => unawaited(_addText()) : null,
                ),
                _WordPadLargeAction(
                  icon: Icons.layers_outlined,
                  label: 'Camadas',
                  onPressed: _showLayers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordPadViewRibbon() {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordPadRibbonGroup(
            label: 'Zoom',
            minWidth: compact ? 200 : 240,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WordPadLargeAction(
                  icon: Icons.zoom_out,
                  label: 'Menos',
                  onPressed: () => _zoomBy(0.85),
                ),
                _WordPadLargeAction(
                  icon: Icons.looks_one_outlined,
                  label: '100%',
                  onPressed: _resetZoom,
                ),
                _WordPadLargeAction(
                  icon: Icons.zoom_in,
                  label: 'Mais',
                  onPressed: () => _zoomBy(1.15),
                ),
              ],
            ),
          ),
          WordPadRibbonGroup(
            label: 'Mostrar ou ocultar',
            minWidth: compact ? 180 : 230,
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: const Text('Régua'),
              value: _documentRulerVisible,
              onChanged: (value) => setState(() => _documentRulerVisible = value),
            ),
          ),
          WordPadRibbonGroup(
            label: 'Ferramentas',
            minWidth: compact ? 170 : 210,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WordPadLargeAction(
                  icon: Icons.pan_tool_alt_outlined,
                  label: 'Mão',
                  onPressed: () => setState(() {
                    _handMode = true;
                    _pointerMode = false;
                    _eraserMode = false;
                    _lassoMode = false;
                  }),
                ),
                _WordPadLargeAction(
                  icon: Icons.select_all,
                  label: 'Selecionar',
                  onPressed: () => setState(() {
                    _pointerMode = true;
                    _handMode = false;
                    _eraserMode = false;
                    _lassoMode = false;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showWordPadFileMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Novo caderno'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_createNotebook());
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renomear caderno'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_renameNotebook());
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Nova página'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_addPage());
              },
            ),
          ],
        ),
      ),
    );
  }
'''
screen = screen[:old_toolbar_start] + new_toolbar + screen[old_toolbar_end:]
screen_path.write_text(screen)

# ---------- update legacy rich-text contract ----------
test_path = root / 'test/notebook_rich_text_contract_test.dart'
test = test_path.read_text()
test = test.replace("contains('_buildTextFormattingToolbar')", "contains('_buildWordPadHomeRibbon')")
test = test.replace("contains(\"labelText: 'Fonte'\")", "contains(\"WordPadRibbonGroup(\\n            label: 'Fonte'\")")
test = test.replace("contains(\"labelText: 'Tamanho'\")", "contains(" + '"wordpad-size-"' + ")")
test = test.replace("test('notebook text formatting persists in schema v9'", "test('notebook text formatting persists in schema v10'")
test = test.replace("contains('schemaVersion = 9')", "contains('schemaVersion = 10')")
test_path.write_text(test)

# ---------- add fidelity contract ----------
fidelity = root / 'test/notebook_wordpad_fidelity_contract_test.dart'
fidelity.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook uses a WordPad-like ribbon, ruler and status bar', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart').readAsStringSync();

    expect(screen, contains('NotebookWordPadRibbon('));
    expect(screen, contains('NotebookWordPadRuler('));
    expect(screen, contains('NotebookWordPadStatusBar('));
    expect(screen, contains("label: 'Fonte'"));
    expect(screen, contains("label: 'Parágrafo'"));
    expect(screen, contains("label: 'Inserir'"));
    expect(screen, contains("label: 'Edição'"));
    expect(chrome, contains("'Arquivo'"));
    expect(chrome, contains("tab('Início'"));
    expect(chrome, contains("tab('Desenho'"));
    expect(chrome, contains("tab('Exibir'"));
    expect(chrome, contains('Slider('));
  });

  test('paragraph alignment is persisted in schema v10', () {
    final db = File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final model = File('lib/src/core/notebook/notebook_object_models.dart').readAsStringSync();
    final store = File('lib/src/core/storage/local_notebook_object_store.dart').readAsStringSync();
    final layer = File('lib/src/widgets/notebook_object_layer.dart').readAsStringSync();

    expect(db, contains('schemaVersion = 10'));
    expect(db, contains('text_align TEXT'));
    expect(model, contains('enum NotebookTextAlign'));
    expect(model, contains('final NotebookTextAlign textAlign'));
    expect(store, contains('object.textAlign.dbValue'));
    expect(store, contains("row['text_align']"));
    expect(layer, contains('textAlign: object.textAlign.flutterValue'));
    expect(layer, contains('textAlign: widget.object.textAlign.flutterValue'));
  });
}
''')

print('WordPad fidelity patch applied')

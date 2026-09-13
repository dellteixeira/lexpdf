from pathlib import Path
import re

root = Path('apps/lexpdf_app')

p = root / 'lib/src/core/notebook/notebook_object_models.dart'
s = p.read_text()
s = s.replace("    this.textValue,\n    this.fontSize,\n    this.imagePath,\n", "    this.textValue,\n    this.fontSize,\n    this.fontFamily,\n    this.fontBold = false,\n    this.fontItalic = false,\n    this.fontUnderline = false,\n    this.imagePath,\n")
s = s.replace("  final String? textValue;\n  final double? fontSize;\n  final String? imagePath;\n", "  final String? textValue;\n  final double? fontSize;\n  final String? fontFamily;\n  final bool fontBold;\n  final bool fontItalic;\n  final bool fontUnderline;\n  final String? imagePath;\n")
s = s.replace("    String? textValue,\n    double? fontSize,\n    String? imagePath,\n", "    String? textValue,\n    double? fontSize,\n    String? fontFamily,\n    bool clearFontFamily = false,\n    bool? fontBold,\n    bool? fontItalic,\n    bool? fontUnderline,\n    String? imagePath,\n")
s = s.replace("      textValue: textValue ?? this.textValue,\n      fontSize: fontSize ?? this.fontSize,\n      imagePath: imagePath ?? this.imagePath,\n", "      textValue: textValue ?? this.textValue,\n      fontSize: fontSize ?? this.fontSize,\n      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),\n      fontBold: fontBold ?? this.fontBold,\n      fontItalic: fontItalic ?? this.fontItalic,\n      fontUnderline: fontUnderline ?? this.fontUnderline,\n      imagePath: imagePath ?? this.imagePath,\n")
p.write_text(s)

p = root / 'lib/src/core/storage/local_database.dart'
s = p.read_text().replace('static const int schemaVersion = 8;', 'static const int schemaVersion = 9;')
needle = "    }\n  }\n\n  void close() => database.dispose();\n}"
migration = """    }

    if (version < 9) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('ALTER TABLE notebook_objects ADD COLUMN font_family TEXT;');
        database.execute('ALTER TABLE notebook_objects ADD COLUMN font_bold INTEGER NOT NULL DEFAULT 0 CHECK(font_bold IN (0, 1));');
        database.execute('ALTER TABLE notebook_objects ADD COLUMN font_italic INTEGER NOT NULL DEFAULT 0 CHECK(font_italic IN (0, 1));');
        database.execute('ALTER TABLE notebook_objects ADD COLUMN font_underline INTEGER NOT NULL DEFAULT 0 CHECK(font_underline IN (0, 1));');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['9', 'schema_version']);
        database.userVersion = 9;
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  void close() => database.dispose();
}"""
if needle not in s:
    raise SystemExit('local_database tail marker not found')
p.write_text(s.replace(needle, migration))

p = root / 'lib/src/core/storage/local_notebook_object_store.dart'
s = p.read_text()
s = s.replace("        fill_color_value, stroke_width, text_value, font_size, image_path,\n        created_at, updated_at\n      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);\n", "        fill_color_value, stroke_width, text_value, font_size, font_family,\n        font_bold, font_italic, font_underline, image_path, created_at, updated_at\n      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);\n")
s = s.replace("      object.textValue,\n      object.fontSize,\n      object.imagePath,\n", "      object.textValue,\n      object.fontSize,\n      object.fontFamily,\n      object.fontBold ? 1 : 0,\n      object.fontItalic ? 1 : 0,\n      object.fontUnderline ? 1 : 0,\n      object.imagePath,\n")
s = s.replace("        textValue: object.textValue,\n        fontSize: object.fontSize,\n        imagePath: object.imagePath,\n", "        textValue: object.textValue,\n        fontSize: object.fontSize,\n        fontFamily: object.fontFamily,\n        fontBold: object.fontBold,\n        fontItalic: object.fontItalic,\n        fontUnderline: object.fontUnderline,\n        imagePath: object.imagePath,\n")
s = s.replace("        textValue: row['text_value'] as String?,\n        fontSize: (row['font_size'] as num?)?.toDouble(),\n        imagePath: row['image_path'] as String?,\n", "        textValue: row['text_value'] as String?,\n        fontSize: (row['font_size'] as num?)?.toDouble(),\n        fontFamily: row['font_family'] as String?,\n        fontBold: (row['font_bold'] as int? ?? 0) != 0,\n        fontItalic: (row['font_italic'] as int? ?? 0) != 0,\n        fontUnderline: (row['font_underline'] as int? ?? 0) != 0,\n        imagePath: row['image_path'] as String?,\n")
p.write_text(s)

p = root / 'lib/src/widgets/notebook_object_layer.dart'
s = p.read_text()
s = s.replace("    this.onObjectDoubleTap,\n    this.selectedId,\n", "    this.onObjectDoubleTap,\n    this.editingTextId,\n    this.onTextChanged,\n    this.onTextEditingComplete,\n    this.selectedId,\n")
s = s.replace("  final ValueChanged<NotebookObject>? onObjectDoubleTap;\n", "  final ValueChanged<NotebookObject>? onObjectDoubleTap;\n  final String? editingTextId;\n  final ValueChanged<NotebookObject>? onTextChanged;\n  final ValueChanged<NotebookObject>? onTextEditingComplete;\n")
old = """                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ObjectVisual(object: object),
                      if (selected)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.7,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
"""
new = """                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (object.type == NotebookObjectType.text &&
                          widget.editingTextId == object.id)
                        _InlineNotebookTextEditor(
                          object: object,
                          onChanged: widget.onTextChanged,
                          onEditingComplete: widget.onTextEditingComplete,
                        )
                      else
                        _ObjectVisual(object: object),
                      if (selected && widget.editingTextId != object.id)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.7,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
"""
if old not in s:
    raise SystemExit('object visual block not found')
s = s.replace(old, new)
s = s.replace("          style: TextStyle(\n            color: Color(object.colorValue),\n            fontSize: object.fontSize ?? 18,\n          ),\n", "          style: TextStyle(\n            color: Color(object.colorValue),\n            fontSize: object.fontSize ?? 18,\n            fontFamily: object.fontFamily,\n            fontWeight: object.fontBold ? FontWeight.bold : FontWeight.normal,\n            fontStyle: object.fontItalic ? FontStyle.italic : FontStyle.normal,\n            decoration: object.fontUnderline ? TextDecoration.underline : null,\n          ),\n")
insert_before = 'class _NotebookShapePainter extends CustomPainter {'
editor = '''class _InlineNotebookTextEditor extends StatefulWidget {
  const _InlineNotebookTextEditor({
    required this.object,
    this.onChanged,
    this.onEditingComplete,
  });

  final NotebookObject object;
  final ValueChanged<NotebookObject>? onChanged;
  final ValueChanged<NotebookObject>? onEditingComplete;

  @override
  State<_InlineNotebookTextEditor> createState() => _InlineNotebookTextEditorState();
}

class _InlineNotebookTextEditorState extends State<_InlineNotebookTextEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.object.textValue ?? '');
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _focusNode = FocusNode(debugLabel: 'notebook-inline-text');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _InlineNotebookTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = widget.object.textValue ?? '';
    if (!_focusNode.hasFocus && external != _controller.text) {
      _controller.value = TextEditingValue(
        text: external,
        selection: TextSelection.collapsed(offset: external.length),
      );
    }
  }

  TextStyle get _style => TextStyle(
        color: Color(widget.object.colorValue),
        fontSize: widget.object.fontSize ?? 20,
        fontFamily: widget.object.fontFamily,
        fontWeight: widget.object.fontBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: widget.object.fontItalic ? FontStyle.italic : FontStyle.normal,
        decoration: widget.object.fontUnderline ? TextDecoration.underline : null,
        height: 1.25,
      );

  void _emit() {
    widget.onChanged?.call(
      widget.object.copyWith(
        textValue: _controller.text,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _finish() {
    _emit();
    widget.onEditingComplete?.call(
      widget.object.copyWith(
        textValue: _controller.text,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 1.4,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: _style,
        cursorColor: Theme.of(context).colorScheme.primary,
        decoration: const InputDecoration(
          isCollapsed: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          border: InputBorder.none,
        ),
        onChanged: (_) => _emit(),
        onEditingComplete: _finish,
        onTapOutside: (_) {
          _focusNode.unfocus();
          _finish();
        },
      ),
    );
  }
}

'''
if insert_before not in s:
    raise SystemExit('shape painter marker missing')
p.write_text(s.replace(insert_before, editor + insert_before))

p = root / 'lib/src/screens/layered_notebook_screen.dart'
s = p.read_text()
s = s.replace("  String? _selectedObjectId;\n  bool _suppressMutationHistory = false;\n", "  String? _selectedObjectId;\n  String? _editingTextObjectId;\n  bool _suppressMutationHistory = false;\n")
s = s.replace("              _buildToolbar(),\n              const Divider(height: 1),\n              Expanded(child: _buildPageViewport(page)),\n", "              _buildToolbar(),\n              if (_editingTextObjectId != null ||\n                  _selectedObject?.type == NotebookObjectType.text)\n                _buildTextFormattingToolbar(),\n              const Divider(height: 1),\n              Expanded(child: _buildPageViewport(page)),\n")
s = s.replace("                          onObjectChanged: _onObjectChanged,\n                          onObjectDoubleTap: _handleObjectDoubleTap,\n                          onSelectionChanged: (id) {\n", "                          onObjectChanged: _onObjectChanged,\n                          onObjectDoubleTap: _handleObjectDoubleTap,\n                          editingTextId: _editingTextObjectId,\n                          onTextChanged: _onTextObjectLiveChanged,\n                          onTextEditingComplete: _finishTextEditing,\n                          onSelectionChanged: (id) {\n")
pattern = re.compile(r"  Future<void> _addText\(\) async \{.*?\n  \}\n\n  Future<void> _addImage", re.S)
replacement = '''  Future<void> _addText() async {
    final page = _currentPage;
    if (page == null || !_canEditActiveLayer) return;
    _recordHistory();
    final now = DateTime.now().toUtc();
    final object = NotebookObject(
      id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',
      pageId: page.id,
      type: NotebookObjectType.text,
      x: 80,
      y: 80,
      width: math.min(520.0, math.max(300.0, page.width - 160)),
      height: 180,
      rotation: 0,
      colorValue: _colorValue,
      strokeWidth: 1,
      textValue: '',
      fontSize: 20,
      createdAt: now,
      updatedAt: now,
    );
    await _persistNewObject(object);
    if (!mounted) return;
    setState(() {
      _pointerMode = true;
      _handMode = false;
      _eraserMode = false;
      _lassoMode = false;
      _selectedObjectId = object.id;
      _editingTextObjectId = object.id;
    });
  }

  Future<void> _addImage'''
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'addText replacement count {count}')
pattern = re.compile(r"  void _handleObjectDoubleTap\(NotebookObject object\) \{.*?\n  \}\n\n  Future<void> _recognizeSelectedInk", re.S)
replacement = '''  void _handleObjectDoubleTap(NotebookObject object) {
    if (object.type == NotebookObjectType.text && _canEditActiveLayer) {
      _beginTextEditing(object);
    }
  }

  void _beginTextEditing(NotebookObject object) {
    if (!_canEditActiveLayer || object.type != NotebookObjectType.text) return;
    if (_editingTextObjectId != object.id) _recordHistory();
    setState(() {
      _selectedObjectId = object.id;
      _editingTextObjectId = object.id;
      _pointerMode = true;
      _handMode = false;
      _eraserMode = false;
      _lassoMode = false;
    });
  }

  void _onTextObjectLiveChanged(NotebookObject object) {
    final index = _allObjects.indexWhere((item) => item.id == object.id);
    if (index < 0 || !_canEditActiveLayer) return;
    final next = [..._allObjects]..[index] = object;
    setState(() => _allObjects = next);
    unawaited(_objectStore.upsert(object));
  }

  void _finishTextEditing(NotebookObject object) {
    _onTextObjectLiveChanged(object);
    if (!mounted) return;
    setState(() => _editingTextObjectId = null);
  }

  void _setSelectedTextStyle({
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    String? fontFamily,
    bool clearFontFamily = false,
    int? colorValue,
  }) {
    final object = _selectedObject;
    if (object == null || object.type != NotebookObjectType.text) return;
    _onObjectChanged(
      object.copyWith(
        fontBold: bold,
        fontItalic: italic,
        fontUnderline: underline,
        fontSize: fontSize,
        fontFamily: fontFamily,
        clearFontFamily: clearFontFamily,
        colorValue: colorValue,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Widget _buildTextFormattingToolbar() {
    final object = _selectedObject;
    if (object == null || object.type != NotebookObjectType.text) {
      return const SizedBox.shrink();
    }
    const fontSizes = <double>[12, 14, 16, 18, 20, 24, 28, 32, 36, 48];
    const fonts = <String, String?>{
      'Padrão': null,
      'Arial': 'Arial',
      'Roboto': 'Roboto',
      'Serif': 'serif',
      'Monoespaçada': 'monospace',
    };
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          children: [
            IconButton(
              tooltip: 'Editar texto na folha',
              isSelected: _editingTextObjectId == object.id,
              onPressed: () => _beginTextEditing(object),
              icon: const Icon(Icons.text_fields),
            ),
            const VerticalDivider(width: 12),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                key: ValueKey('font-${object.fontFamily}'),
                initialValue: fonts.entries
                    .firstWhere(
                      (entry) => entry.value == object.fontFamily,
                      orElse: () => fonts.entries.first,
                    )
                    .key,
                decoration: const InputDecoration(
                  labelText: 'Fonte',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                items: fonts.keys
                    .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                    .toList(growable: false),
                onChanged: (label) {
                  if (label == null) return;
                  final family = fonts[label];
                  _setSelectedTextStyle(
                    fontFamily: family,
                    clearFontFamily: family == null,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: DropdownButtonFormField<double>(
                key: ValueKey('size-${object.fontSize}'),
                initialValue: fontSizes.contains(object.fontSize ?? 20)
                    ? (object.fontSize ?? 20)
                    : 20,
                decoration: const InputDecoration(
                  labelText: 'Tamanho',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Negrito',
              isSelected: object.fontBold,
              onPressed: () => _setSelectedTextStyle(bold: !object.fontBold),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton(
              tooltip: 'Itálico',
              isSelected: object.fontItalic,
              onPressed: () => _setSelectedTextStyle(italic: !object.fontItalic),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton(
              tooltip: 'Sublinhado',
              isSelected: object.fontUnderline,
              onPressed: () => _setSelectedTextStyle(underline: !object.fontUnderline),
              icon: const Icon(Icons.format_underline),
            ),
            PopupMenuButton<int>(
              tooltip: 'Cor da fonte',
              icon: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  const Icon(Icons.format_color_text),
                  Container(width: 22, height: 4, color: Color(object.colorValue)),
                ],
              ),
              itemBuilder: (_) => _palette
                  .map((value) => PopupMenuItem<int>(
                        value: value,
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Color(value),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(value == object.colorValue ? 'Selecionada' : 'Usar cor'),
                          ],
                        ),
                      ))
                  .toList(growable: false),
              onSelected: (value) => _setSelectedTextStyle(colorValue: value),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _editingTextObjectId == object.id
                  ? () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _editingTextObjectId = null);
                    }
                  : () => _beginTextEditing(object),
              icon: Icon(_editingTextObjectId == object.id ? Icons.check : Icons.edit),
              label: Text(_editingTextObjectId == object.id ? 'Concluir' : 'Editar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recognizeSelectedInk'''
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'editText replacement count {count}')
s = s.replace("      onEditTextObject: () {\n        if (selectedObject != null) unawaited(_editTextObject(selectedObject));\n      },\n", "      onEditTextObject: () {\n        if (selectedObject != null) _beginTextEditing(selectedObject);\n      },\n")
p.write_text(s)

p = root / 'test/notebook_rich_text_contract_test.dart'
p.write_text("""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook text is edited inline with cursor and formatting toolbar', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final layer = File('lib/src/widgets/notebook_object_layer.dart').readAsStringSync();
    expect(screen, isNot(contains(\"title: const Text('Inserir texto')\")));
    expect(screen, contains('_editingTextObjectId'));
    expect(screen, contains('_buildTextFormattingToolbar'));
    expect(screen, contains('Icons.format_bold'));
    expect(screen, contains('Icons.format_italic'));
    expect(screen, contains('Icons.format_underline'));
    expect(screen, contains(\"labelText: 'Fonte'\"));
    expect(screen, contains(\"labelText: 'Tamanho'\"));
    expect(screen, contains(\"tooltip: 'Cor da fonte'\"));
    expect(layer, contains('_InlineNotebookTextEditor'));
    expect(layer, contains('TextField('));
    expect(layer, contains('cursorColor:'));
    expect(layer, contains('autofocus: true'));
  });

  test('notebook text formatting persists in schema v9', () {
    final db = File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final model = File('lib/src/core/notebook/notebook_object_models.dart').readAsStringSync();
    final store = File('lib/src/core/storage/local_notebook_object_store.dart').readAsStringSync();
    expect(db, contains('schemaVersion = 9'));
    expect(db, contains('font_family TEXT'));
    expect(db, contains('font_bold INTEGER'));
    expect(db, contains('font_italic INTEGER'));
    expect(db, contains('font_underline INTEGER'));
    expect(model, contains('final String? fontFamily'));
    expect(model, contains('final bool fontBold'));
    expect(model, contains('final bool fontItalic'));
    expect(model, contains('final bool fontUnderline'));
    expect(store, contains(\"row['font_family']\"));
    expect(store, contains(\"row['font_bold']\"));
  });
}
""")

print('rich notebook text patch applied')

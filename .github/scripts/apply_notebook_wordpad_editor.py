from pathlib import Path

root = Path('apps/lexpdf_app')

screen_path = root / 'lib/src/screens/layered_notebook_screen.dart'
screen = screen_path.read_text()

screen = screen.replace(
"""  static const double _widthUp = 1.15;\n  static const InkShapeRecognizer _shapeRecognizer = InkShapeRecognizer();\n""",
"""  static const double _widthUp = 1.15;\n  static const String _defaultNotebookFontFamily = 'Arial';\n  static const double _defaultNotebookFontSize = 12;\n  static const InkShapeRecognizer _shapeRecognizer = InkShapeRecognizer();\n""",
)

screen = screen.replace(
"""  bool _pointerMode = false;\n  bool _handMode = false;\n  bool _rulerMode = false;\n  double _zoom = 1.0;\n  String? _selectedObjectId;\n  String? _editingTextObjectId;\n""",
"""  bool _pointerMode = true;\n  bool _handMode = false;\n  bool _rulerMode = false;\n  double _zoom = 1.0;\n  String? _selectedObjectId;\n  String? _editingTextObjectId;\n  String _defaultTextFontFamily = _defaultNotebookFontFamily;\n  double _defaultTextFontSize = _defaultNotebookFontSize;\n  bool _defaultTextBold = false;\n  bool _defaultTextItalic = false;\n  bool _defaultTextUnderline = false;\n  int _defaultTextColorValue = 0xFF000000;\n""",
)

screen = screen.replace(
"""      _selectedObjectId = null;\n      _pointerMode = false;\n      _handMode = false;\n""",
"""      _selectedObjectId = null;\n      _pointerMode = true;\n      _handMode = false;\n""",
2,
)

screen = screen.replace(
"""              _buildLayerStatus(),\n              _buildToolbar(),\n              if (_editingTextObjectId != null ||\n                  _selectedObject?.type == NotebookObjectType.text)\n                _buildTextFormattingToolbar(),\n""",
"""              _buildLayerStatus(),\n              _buildTextFormattingToolbar(),\n              _buildToolbar(),\n""",
)

screen = screen.replace(
"""                      borderRadius: BorderRadius.circular(12),\n""",
"""                      borderRadius: BorderRadius.circular(4),\n""",
1,
)

screen = screen.replace(
"""                          onTextEditingComplete: _finishTextEditing,\n                          onSelectionChanged: (id) {\n""",
"""                          onTextEditingComplete: _finishTextEditing,\n                          onEmptyTap: () {\n                            if (_pointerMode && _canEditActiveLayer) {\n                              unawaited(_addText());\n                            }\n                          },\n                          onSelectionChanged: (id) {\n""",
)

old_add_text = """  Future<void> _addText() async {\n    final page = _currentPage;\n    if (page == null || !_canEditActiveLayer) return;\n    _recordHistory();\n    final now = DateTime.now().toUtc();\n    final object = NotebookObject(\n      id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',\n      pageId: page.id,\n      type: NotebookObjectType.text,\n      x: 80,\n      y: 80,\n      width: math.min(520.0, math.max(300.0, page.width - 160)),\n      height: 180,\n      rotation: 0,\n      colorValue: _colorValue,\n      strokeWidth: 1,\n      textValue: '',\n      fontSize: 20,\n      createdAt: now,\n      updatedAt: now,\n    );\n    await _persistNewObject(object);\n    if (!mounted) return;\n    setState(() {\n      _pointerMode = true;\n      _handMode = false;\n      _eraserMode = false;\n      _lassoMode = false;\n      _selectedObjectId = object.id;\n      _editingTextObjectId = object.id;\n    });\n  }\n"""
new_add_text = """  Future<void> _addText() async {\n    final page = _currentPage;\n    if (page == null || !_canEditActiveLayer) return;\n\n    for (final existing in _activeObjects) {\n      if (existing.type == NotebookObjectType.text) {\n        _beginTextEditing(existing);\n        return;\n      }\n    }\n\n    _recordHistory();\n    final now = DateTime.now().toUtc();\n    const marginX = 56.0;\n    const marginY = 56.0;\n    final object = NotebookObject(\n      id: 'object-${now.microsecondsSinceEpoch.toRadixString(36)}',\n      pageId: page.id,\n      type: NotebookObjectType.text,\n      x: marginX,\n      y: marginY,\n      width: math.max(120.0, page.width - (marginX * 2)),\n      height: math.max(120.0, page.height - (marginY * 2)),\n      rotation: 0,\n      colorValue: _defaultTextColorValue,\n      strokeWidth: 1,\n      textValue: '',\n      fontSize: _defaultTextFontSize,\n      fontFamily: _defaultTextFontFamily,\n      fontBold: _defaultTextBold,\n      fontItalic: _defaultTextItalic,\n      fontUnderline: _defaultTextUnderline,\n      createdAt: now,\n      updatedAt: now,\n    );\n    await _persistNewObject(object);\n    if (!mounted) return;\n    setState(() {\n      _pointerMode = true;\n      _handMode = false;\n      _eraserMode = false;\n      _lassoMode = false;\n      _selectedObjectId = object.id;\n      _editingTextObjectId = object.id;\n    });\n  }\n"""
if old_add_text not in screen:
    raise SystemExit('old _addText block not found')
screen = screen.replace(old_add_text, new_add_text)

old_set_style = """  void _setSelectedTextStyle({\n    bool? bold,\n    bool? italic,\n    bool? underline,\n    double? fontSize,\n    String? fontFamily,\n    bool clearFontFamily = false,\n    int? colorValue,\n  }) {\n    final object = _selectedObject;\n    if (object == null || object.type != NotebookObjectType.text) return;\n    _onObjectChanged(\n      object.copyWith(\n        fontBold: bold,\n        fontItalic: italic,\n        fontUnderline: underline,\n        fontSize: fontSize,\n        fontFamily: fontFamily,\n        clearFontFamily: clearFontFamily,\n        colorValue: colorValue,\n        updatedAt: DateTime.now().toUtc(),\n      ),\n    );\n  }\n"""
new_set_style = """  void _setSelectedTextStyle({\n    bool? bold,\n    bool? italic,\n    bool? underline,\n    double? fontSize,\n    String? fontFamily,\n    bool clearFontFamily = false,\n    int? colorValue,\n  }) {\n    final object = _selectedObject;\n    if (object == null || object.type != NotebookObjectType.text) {\n      setState(() {\n        if (bold != null) _defaultTextBold = bold;\n        if (italic != null) _defaultTextItalic = italic;\n        if (underline != null) _defaultTextUnderline = underline;\n        if (fontSize != null) _defaultTextFontSize = fontSize;\n        if (fontFamily != null) _defaultTextFontFamily = fontFamily;\n        if (clearFontFamily) {\n          _defaultTextFontFamily = _defaultNotebookFontFamily;\n        }\n        if (colorValue != null) _defaultTextColorValue = colorValue;\n      });\n      return;\n    }\n    _onObjectChanged(\n      object.copyWith(\n        fontBold: bold,\n        fontItalic: italic,\n        fontUnderline: underline,\n        fontSize: fontSize,\n        fontFamily: fontFamily,\n        clearFontFamily: clearFontFamily,\n        colorValue: colorValue,\n        updatedAt: DateTime.now().toUtc(),\n      ),\n    );\n  }\n"""
if old_set_style not in screen:
    raise SystemExit('old _setSelectedTextStyle block not found')
screen = screen.replace(old_set_style, new_set_style)

start = screen.index('  Widget _buildTextFormattingToolbar() {')
end = screen.index('\n  Future<void> _recognizeSelectedInk()', start)
new_toolbar = r'''  Widget _buildTextFormattingToolbar() {
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

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          children: [
            FilledButton.tonalIcon(
              onPressed: _canEditActiveLayer ? () => unawaited(_addText()) : null,
              icon: const Icon(Icons.edit_note),
              label: Text(object == null ? 'Escrever' : 'Editar texto'),
            ),
            const VerticalDivider(width: 16),
            SizedBox(
              width: 148,
              child: DropdownButtonFormField<String>(
                key: ValueKey('font-$currentFamily'),
                initialValue: fonts.containsValue(currentFamily)
                    ? currentFamily
                    : _defaultNotebookFontFamily,
                decoration: const InputDecoration(
                  labelText: 'Fonte',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                items: fonts.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.value,
                          child: Text(entry.key),
                        ))
                    .toList(growable: false),
                onChanged: (family) {
                  if (family != null) _setSelectedTextStyle(fontFamily: family);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: DropdownButtonFormField<double>(
                key: ValueKey('size-$currentSize'),
                initialValue: fontSizes.contains(currentSize)
                    ? currentSize
                    : _defaultNotebookFontSize,
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
              isSelected: currentBold,
              onPressed: () => _setSelectedTextStyle(bold: !currentBold),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton(
              tooltip: 'Itálico',
              isSelected: currentItalic,
              onPressed: () => _setSelectedTextStyle(italic: !currentItalic),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton(
              tooltip: 'Sublinhado',
              isSelected: currentUnderline,
              onPressed: () => _setSelectedTextStyle(underline: !currentUnderline),
              icon: const Icon(Icons.format_underline),
            ),
            PopupMenuButton<int>(
              tooltip: 'Cor da fonte',
              icon: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  const Icon(Icons.format_color_text),
                  Container(width: 22, height: 4, color: Color(currentColor)),
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
                            Text(value == currentColor ? 'Selecionada' : 'Usar cor'),
                          ],
                        ),
                      ))
                  .toList(growable: false),
              onSelected: (value) => _setSelectedTextStyle(colorValue: value),
            ),
            const VerticalDivider(width: 16),
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
          ],
        ),
      ),
    );
  }
'''
screen = screen[:start] + new_toolbar + screen[end:]
screen_path.write_text(screen)

layer_path = root / 'lib/src/widgets/notebook_object_layer.dart'
layer = layer_path.read_text()
layer = layer.replace(
"""    this.onTextEditingComplete,\n    this.selectedId,\n""",
"""    this.onTextEditingComplete,\n    this.onEmptyTap,\n    this.selectedId,\n""",
)
layer = layer.replace(
"""  final ValueChanged<NotebookObject>? onTextEditingComplete;\n""",
"""  final ValueChanged<NotebookObject>? onTextEditingComplete;\n  final VoidCallback? onEmptyTap;\n""",
)
layer = layer.replace(
"""            onTap: () => widget.onSelectionChanged(null),\n""",
"""            onTap: () {\n              widget.onSelectionChanged(null);\n              widget.onEmptyTap?.call();\n            },\n""",
1,
)
layer = layer.replace(
"""    final width = math.max(_minimumObjectExtent, object.width);\n    final height = math.max(_minimumObjectExtent, object.height);\n\n    return Positioned(\n""",
"""    final width = math.max(_minimumObjectExtent, object.width);\n    final height = math.max(_minimumObjectExtent, object.height);\n    final editingText = object.type == NotebookObjectType.text &&\n        widget.editingTextId == object.id;\n\n    return Positioned(\n""",
)
layer = layer.replace(
"""                cursor: SystemMouseCursors.move,\n""",
"""                cursor: editingText ? SystemMouseCursors.text : SystemMouseCursors.move,\n""",
1,
)
layer = layer.replace(
"""                  onPanStart: (_) {\n                    widget.onSelectionChanged(object.id);\n                    _working = object;\n                  },\n                  onPanUpdate: (details) {\n                    final current = _working ?? object;\n                    setState(() {\n                      _working = current.copyWith(\n                        x: current.x + details.delta.dx,\n                        y: current.y + details.delta.dy,\n                        updatedAt: DateTime.now().toUtc(),\n                      );\n                    });\n                  },\n                  onPanEnd: (_) => _commitWorking(),\n                  onPanCancel: _cancelWorking,\n""",
"""                  onPanStart: editingText\n                      ? null\n                      : (_) {\n                          widget.onSelectionChanged(object.id);\n                          _working = object;\n                        },\n                  onPanUpdate: editingText\n                      ? null\n                      : (details) {\n                          final current = _working ?? object;\n                          setState(() {\n                            _working = current.copyWith(\n                              x: current.x + details.delta.dx,\n                              y: current.y + details.delta.dy,\n                              updatedAt: DateTime.now().toUtc(),\n                            );\n                          });\n                        },\n                  onPanEnd: editingText ? null : (_) => _commitWorking(),\n                  onPanCancel: editingText ? null : _cancelWorking,\n""",
)
layer = layer.replace(
"""                      if (object.type == NotebookObjectType.text &&\n                          widget.editingTextId == object.id)\n""",
"""                      if (editingText)\n""",
1,
)
layer = layer.replace(
"""            if (selected) ...[\n""",
"""            if (selected && !editingText) ...[\n""",
1,
)
layer = layer.replace("fontSize: object.fontSize ?? 18,", "fontSize: object.fontSize ?? 12,")
layer = layer.replace("fontFamily: object.fontFamily,", "fontFamily: object.fontFamily ?? 'Arial',", 1)
layer = layer.replace("fontSize: widget.object.fontSize ?? 20,", "fontSize: widget.object.fontSize ?? 12,")
layer = layer.replace("fontFamily: widget.object.fontFamily,", "fontFamily: widget.object.fontFamily ?? 'Arial',", 1)
old_editor_build = """  Widget build(BuildContext context) {\n    return DecoratedBox(\n      decoration: BoxDecoration(\n        color: Colors.transparent,\n        border: Border.all(\n          color: Theme.of(context).colorScheme.primary,\n          width: 1.4,\n        ),\n      ),\n      child: TextField(\n"""
new_editor_build = """  Widget build(BuildContext context) {\n    return TextField(\n"""
if old_editor_build not in layer:
    raise SystemExit('inline editor wrapper not found')
layer = layer.replace(old_editor_build, new_editor_build)
layer = layer.replace(
"""        onTapOutside: (_) {\n          _focusNode.unfocus();\n          _finish();\n        },\n      ),\n    );\n  }\n}\n""",
"""      onTapOutside: (_) {\n        _focusNode.unfocus();\n        _finish();\n      },\n    );\n  }\n}\n""",
1,
)
layer_path.write_text(layer)

test_path = root / 'test/notebook_wordpad_editor_contract_test.dart'
test_path.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook exposes WordPad-like always-visible text ribbon', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();

    expect(screen, contains("_defaultNotebookFontFamily = 'Arial'"));
    expect(screen, contains('_defaultNotebookFontSize = 12'));
    expect(screen, contains('_buildTextFormattingToolbar(),'));
    expect(screen, isNot(contains("if (_editingTextObjectId != null ||")));
    expect(screen, contains("labelText: 'Fonte'"));
    expect(screen, contains("labelText: 'Tamanho'"));
    expect(screen, contains("tooltip: 'Negrito'"));
    expect(screen, contains("tooltip: 'Itálico'"));
    expect(screen, contains("tooltip: 'Sublinhado'"));
    expect(screen, contains("tooltip: 'Cor da fonte'"));
  });

  test('notebook text starts as Arial 12 and edits directly on page', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final layer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();

    expect(screen, contains('fontSize: _defaultTextFontSize'));
    expect(screen, contains('fontFamily: _defaultTextFontFamily'));
    expect(screen, contains('fontBold: _defaultTextBold'));
    expect(screen, contains('fontItalic: _defaultTextItalic'));
    expect(screen, contains('fontUnderline: _defaultTextUnderline'));
    expect(screen, contains('page.height - (marginY * 2)'));
    expect(screen, contains('onEmptyTap: () {'));
    expect(layer, contains('widget.onEmptyTap?.call()'));
    expect(layer, contains('editingText ? SystemMouseCursors.text'));
    expect(layer, contains("fontFamily: widget.object.fontFamily ?? 'Arial'"));
    expect(layer, contains('fontSize: widget.object.fontSize ?? 12'));
    expect(layer, isNot(contains('border: Border.all(\n          color: Theme.of(context).colorScheme.primary,\n          width: 1.4')));
  });
}
''')

print('notebook WordPad editor patch applied')

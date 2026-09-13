from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2] if '.github' in str(Path(__file__).resolve()) else Path.cwd()
APP = ROOT / 'apps' / 'lexpdf_app'


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def write(rel, text):
    (ROOT / rel).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 occurrence, found {count}')
    return text.replace(old, new, 1)


def sub_once(text, pattern, replacement, label, flags=0):
    result, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 regex match, found {count}')
    return result


# Schema v11: one canonical rich document per notebook page.
path = 'apps/lexpdf_app/lib/src/core/storage/local_database.dart'
text = read(path)
text = replace_once(
    text,
    'static const int schemaVersion = 10;',
    'static const int schemaVersion = 11;',
    'schemaVersion 11',
)
needle = '''    if (version < 10) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute(
          "ALTER TABLE notebook_objects ADD COLUMN text_align TEXT NOT NULL DEFAULT 'left' CHECK(text_align IN ('left', 'center', 'right', 'justify'));",
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
'''
replacement = needle + """
    if (version < 11) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE notebook_page_documents (
            page_id TEXT PRIMARY KEY REFERENCES notebook_pages(id) ON DELETE CASCADE,
            document_json TEXT NOT NULL,
            migrated_legacy_text INTEGER NOT NULL DEFAULT 0 CHECK(migrated_legacy_text IN (0, 1)),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', [
          '11',
          'schema_version',
        ]);
        database.userVersion = 11;
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
"""
text = replace_once(text, needle, replacement, 'v11 migration insertion')
write(path, text)


# Positioned object layer: legacy text rows stay in DB but are never rendered
# or edited. Text editing belongs exclusively to FluentDocument.
path = 'apps/lexpdf_app/lib/src/widgets/notebook_object_layer.dart'
text = read(path)
text = sub_once(
    text,
    r"TextAlign _notebookFlutterTextAlign\(NotebookTextAlign value\) => switch \(value\) \{.*?\};\n\n",
    '',
    'remove old TextAlign mapper',
    re.S,
)
text = text.replace('    this.editingTextId,\n', '')
text = text.replace('    this.onTextChanged,\n', '')
text = text.replace('    this.onTextEditingComplete,\n', '')
text = text.replace('    this.onEmptyTap,\n', '')
text = text.replace('  final String? editingTextId;\n', '')
text = text.replace('  final ValueChanged<NotebookObject>? onTextChanged;\n', '')
text = text.replace('  final ValueChanged<NotebookObject>? onTextEditingComplete;\n', '')
text = text.replace('  final VoidCallback? onEmptyTap;\n', '')
text = replace_once(
    text,
    '''            onTap: () {
              widget.onSelectionChanged(null);
              widget.onEmptyTap?.call();
            },''',
    '''            onTap: () => widget.onSelectionChanged(null),''',
    'remove empty-tap text creation',
)
new_build_object = '''  Widget _buildObject(NotebookObject object, bool selected) {
    final width = math.max(_minimumObjectExtent, object.width);
    final height = math.max(_minimumObjectExtent, object.height);

    return Positioned(
      left: object.x,
      top: object.y,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: object.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (_) => widget.onSelectionChanged(object.id),
                  onTap: () => widget.onSelectionChanged(object.id),
                  onDoubleTap: () {
                    widget.onSelectionChanged(object.id);
                    widget.onObjectDoubleTap?.call(object);
                  },
                  onPanStart: (_) {
                    widget.onSelectionChanged(object.id);
                    _working = object;
                  },
                  onPanUpdate: (details) {
                    final current = _working ?? object;
                    setState(() {
                      _working = current.copyWith(
                        x: current.x + details.delta.dx,
                        y: current.y + details.delta.dy,
                        updatedAt: DateTime.now().toUtc(),
                      );
                    });
                  },
                  onPanEnd: (_) => _commitWorking(),
                  onPanCancel: _cancelWorking,
                  child: Stack(
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
                ),
              ),
            ),
            if (selected) ...[
              _buildResizeHandle(object, _ResizeHandle.topLeft),
              _buildResizeHandle(object, _ResizeHandle.topRight),
              _buildResizeHandle(object, _ResizeHandle.bottomLeft),
              _buildResizeHandle(object, _ResizeHandle.bottomRight),
            ],
          ],
        ),
      ),
    );
  }

'''
text = sub_once(
    text,
    r"  Widget _buildObject\(NotebookObject object, bool selected\) \{.*?\n  Widget _buildResizeHandle",
    new_build_object + '  Widget _buildResizeHandle',
    'replace object renderer',
    re.S,
)
text = sub_once(
    text,
    r"    if \(object\.type == NotebookObjectType\.text\) \{.*?\n    \}\n    if \(object\.type == NotebookObjectType\.image\)",
    '''    if (object.type == NotebookObjectType.text) {
      // Kept only for backward-compatible database rows. Canonical notebook
      // text is rendered by NotebookRichDocumentSurface, never as an object.
      return const SizedBox.shrink();
    }
    if (object.type == NotebookObjectType.image)''',
    'hide legacy text visual',
    re.S,
)
text = sub_once(
    text,
    r"\nclass _InlineNotebookTextEditor extends StatefulWidget \{.*?\nclass _NotebookShapePainter",
    '\nclass _NotebookShapePainter',
    'remove inline TextField editor',
    re.S,
)
write(path, text)

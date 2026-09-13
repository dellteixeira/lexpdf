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

path = 'apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart'
text = read(path)
text = replace_once(text, "import 'dart:async';\nimport 'dart:io';", "import 'dart:async';\nimport 'dart:convert';\nimport 'dart:io';", 'screen dart imports')
text = replace_once(text, "import 'package:file_selector/file_selector.dart';\nimport 'package:flutter/material.dart';", "import 'package:file_selector/file_selector.dart';\nimport 'package:fluent_editor/fluent_document.dart';\nimport 'package:flutter/material.dart';", 'screen fluent import')
text = replace_once(text, "import '../core/notebook/notebook_history.dart';\nimport '../core/notebook/notebook_object_models.dart';", "import '../core/notebook/legacy_notebook_text_migrator.dart';\nimport '../core/notebook/notebook_document_file_service.dart';\nimport '../core/notebook/notebook_history.dart';\nimport '../core/notebook/notebook_object_models.dart';", 'screen notebook service imports')
text = replace_once(text, "import '../core/storage/local_notebook_layer_store.dart';\nimport '../core/storage/local_notebook_object_store.dart';", "import '../core/storage/local_notebook_document_store.dart';\nimport '../core/storage/local_notebook_layer_store.dart';\nimport '../core/storage/local_notebook_object_store.dart';", 'screen document store import')
text = replace_once(text, "import '../widgets/notebook_page_background.dart';\nimport '../widgets/notebook_ruler_overlay.dart';", "import '../widgets/notebook_page_background.dart';\nimport '../widgets/notebook_rich_document_surface.dart';\nimport '../widgets/notebook_ruler_overlay.dart';", 'screen rich surface import')
text = replace_once(text, '''  late final LocalNotebookObjectStore _objectStore;
  late final LocalNotebookLayerStore _layerStore;
  late final Future<void> _loadFuture;
''', '''  late final LocalNotebookObjectStore _objectStore;
  late final LocalNotebookLayerStore _layerStore;
  late final LocalNotebookDocumentStore _documentStore;
  late final Future<void> _loadFuture;
  static const LegacyNotebookTextMigrator _legacyTextMigrator =
      LegacyNotebookTextMigrator();
  static const NotebookDocumentFileService _documentFileService =
      NotebookDocumentFileService();
  static const Duration _documentAutosaveDelay = Duration(milliseconds: 650);
  static const int _maximumOfficeFileBytes = 32 * 1024 * 1024;

  FluentDocument? _richDocument;
  String? _richDocumentPageId;
  Timer? _richDocumentSaveTimer;
  int _lastDocumentContentVersion = -1;
  bool _richDocumentMigratedLegacyText = false;
''', 'screen rich document fields')
text = replace_once(text, '''  bool _pointerMode = true;
  bool _handMode = false;''', '''  bool _textMode = true;
  bool _pointerMode = false;
  bool _handMode = false;''', 'screen initial text mode')
text = text.replace('  String? _editingTextObjectId;\n', '')
text = replace_once(text, '''    _objectStore = LocalNotebookObjectStore(widget.inkStore.db);
    _layerStore = LocalNotebookLayerStore(widget.inkStore.db);
    _loadFuture = _loadInitial();''', '''    _objectStore = LocalNotebookObjectStore(widget.inkStore.db);
    _layerStore = LocalNotebookLayerStore(widget.inkStore.db);
    _documentStore = LocalNotebookDocumentStore(widget.inkStore.db);
    _loadFuture = _loadInitial();''', 'init document store')
text = replace_once(text, '''  @override
  void dispose() {
    _toolbarScrollController.dispose();
    _pageTransformController.dispose();
    super.dispose();
  }''', '''  @override
  void dispose() {
    _richDocumentSaveTimer?.cancel();
    final document = _richDocument;
    if (document != null) {
      document.removeListener(_onRichDocumentChanged);
      unawaited(_persistRichDocumentNow());
      document.dispose();
    }
    _toolbarScrollController.dispose();
    _pageTransformController.dispose();
    super.dispose();
  }''', 'dispose rich document')
text = replace_once(text, '''  List<NotebookObject> get _activeObjects => _allObjects
      .where((object) => _objectLayerIds[object.id] == _activeLayerId)
      .toList(growable: false);''', '''  List<NotebookObject> get _activeObjects => _allObjects
      .where(
        (object) =>
            object.type != NotebookObjectType.text &&
            _objectLayerIds[object.id] == _activeLayerId,
      )
      .toList(growable: false);''', 'filter active legacy text')
text = replace_once(text, '''  List<NotebookObject> get _backgroundObjects => _allObjects
      .where((object) {
        final layerId = _objectLayerIds[object.id];
        return layerId != _activeLayerId && _visibleLayerIds.contains(layerId);
      })
      .toList(growable: false);''', '''  List<NotebookObject> get _backgroundObjects => _allObjects
      .where((object) {
        if (object.type == NotebookObjectType.text) return false;
        final layerId = _objectLayerIds[object.id];
        return layerId != _activeLayerId && _visibleLayerIds.contains(layerId);
      })
      .toList(growable: false);''', 'filter background legacy text')
text = replace_once(text, '''    final objects = await _objectStore.listObjects(pageId);
    final strokeMap = await _layerStore.itemLayerMap(''', '''    final objects = await _objectStore.listObjects(pageId);
    await _loadRichDocument(pageId, objects);
    final strokeMap = await _layerStore.itemLayerMap(''', 'load rich document with page content')
write(path, text)

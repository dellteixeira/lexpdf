from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2] if '.github' in str(Path(__file__).resolve()) else Path.cwd()


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
text = sub_once(text, r"  Future<void> _addText\(\) async \{.*?\n  Future<void> _addImage", '''  Future<void> _addText() async {
    _activateTextMode();
  }

  Future<void> _addImage''', 'replace text object creation', re.S)
new_text_mode_methods = r'''  void _activateTextMode() {
    final document = _richDocument;
    if (document == null) return;
    setState(() {
      _textMode = true;
      _pointerMode = false;
      _handMode = false;
      _eraserMode = false;
      _lassoMode = false;
      _selectionCount = 0;
      _selectedObjectId = null;
    });
    _canvasKey.currentState?.clearSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) document.requestEditorFocus();
    });
  }

  void _setSelectedTextStyle({
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    String? fontFamily,
    bool clearFontFamily = false,
    int? colorValue,
    NotebookTextAlign? textAlign,
  }) {
    final document = _richDocument;
    if (document == null) return;
    _activateTextMode();

    if (bold != null && bold != document.pendingStyles.contains('bold')) {
      document.eventHandler.handleBold();
    }
    if (italic != null && italic != document.pendingStyles.contains('italic')) {
      document.eventHandler.handleItalic();
    }
    if (underline != null && underline != document.pendingStyles.contains('underline')) {
      document.eventHandler.handleUnderline();
    }
    if (fontSize != null) document.eventHandler.handleFontSize(fontSize);
    final resolvedFamily = clearFontFamily ? _defaultNotebookFontFamily : fontFamily;
    if (resolvedFamily != null) document.eventHandler.handleFontFamily(resolvedFamily);
    if (colorValue != null) document.eventHandler.handleTextColor(_cssColor(colorValue));
    if (textAlign != null) document.eventHandler.handleTextAlign(textAlign.dbValue);
    document.requestEditorFocus();
  }

'''
text = sub_once(text, r"  void _handleObjectDoubleTap\(NotebookObject object\) \{.*?\n  Widget _buildTextFormattingToolbar\(\) \{", new_text_mode_methods + '  Widget _buildTextFormattingToolbar() {', 'replace old text editing methods', re.S)
text = text.replace('''                  onPressed: _history.canUndo
                      ? () => unawaited(_undoHistory())
                      : null,''', '''                  onPressed: _richDocument == null
                      ? null
                      : () => _richDocument!.undo(),''', 1)
text = text.replace('''                  onPressed: _history.canRedo
                      ? () => unawaited(_redoHistory())
                      : null,''', '''                  onPressed: _richDocument == null
                      ? null
                      : () => _richDocument!.redo(),''', 1)
text = replace_once(text, '''    final duplicate = await widget.inkStore.duplicatePage(page);
    await _objectStore.copyPageObjects(page.id, duplicate.id);
    await _reloadCurrent(pageId: duplicate.id);''', '''    await _persistRichDocumentNow();
    final duplicate = await widget.inkStore.duplicatePage(page);
    await _objectStore.copyPageObjects(page.id, duplicate.id);
    await _documentStore.copyPageDocument(page.id, duplicate.id);
    await _reloadCurrent(pageId: duplicate.id);''', 'copy rich document on page duplication')
text = replace_once(text, '''    final objectIds = _objectLayerIds.entries
        .where((e) => e.value == layer.id)
        .map((e) => e.key)
        .toList();''', '''    final legacyTextIds = _allObjects
        .where((object) => object.type == NotebookObjectType.text)
        .map((object) => object.id)
        .toSet();
    final objectIds = _objectLayerIds.entries
        .where((e) => e.value == layer.id && !legacyTextIds.contains(e.key))
        .map((e) => e.key)
        .toList();''', 'preserve legacy text on clear layer')
file_methods = r'''  Future<void> _openRichDocumentFile() async {
    const group = XTypeGroup(
      label: 'Documentos de texto',
      extensions: ['docx', 'txt', 'doc', 'rtf'],
    );
    final selected = await openFile(acceptedTypeGroups: const [group]);
    if (selected == null) return;
    try {
      final length = await selected.length();
      if (length > _maximumOfficeFileBytes) {
        throw StateError('Arquivo excede o limite seguro de 32 MB.');
      }
      final extension = selected.name.contains('.')
          ? selected.name.split('.').last.toLowerCase()
          : '';
      final root = await _documentFileService.importBytes(
        await selected.readAsBytes(),
        extension,
      );
      final document = _richDocument;
      if (document == null) return;
      document.loadContent(root);
      _richDocumentMigratedLegacyText = true;
      _lastDocumentContentVersion = document.contentVersion;
      await _persistRichDocumentNow();
      _activateTextMode();
      _showNotebookMessage('Documento aberto: ${selected.name}');
    } catch (error) {
      _showNotebookMessage('Não foi possível abrir o documento: $error');
    }
  }

  Future<void> _saveRichDocumentAs(String extension) async {
    final document = _richDocument;
    if (document == null) return;
    final ext = extension.toLowerCase();
    final notebookName = (_currentNotebook?.title ?? 'documento')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '_')
        .trim();
    final safeName = notebookName.isEmpty ? 'documento' : notebookName;
    final group = XTypeGroup(label: ext.toUpperCase(), extensions: [ext]);
    final location = await getSaveLocation(
      suggestedName: '$safeName.$ext',
      acceptedTypeGroups: [group],
    );
    if (location == null) return;
    try {
      final bytes = await _documentFileService.exportBytes(document, ext);
      await File(location.path).writeAsBytes(bytes, flush: true);
      _showNotebookMessage('Arquivo salvo: ${location.path}');
    } catch (error) {
      _showNotebookMessage('Não foi possível salvar .$ext: $error');
    }
  }

  void _showNotebookMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

'''
text = replace_once(text, '''  void _zoomBy(double factor) {''', file_methods + '''  void _zoomBy(double factor) {''', 'insert document file helpers')
text = text.replace('''      _pointerMode = true;
      _handMode = false;''', '''      _textMode = true;
      _pointerMode = false;
      _handMode = false;''', 1)
for forbidden in ['_editingTextObjectId', '_beginTextEditing(', '_onTextObjectLiveChanged(', '_finishTextEditing(']:
    if forbidden in text:
        raise RuntimeError(f'surviving legacy text editor reference: {forbidden}')
write(path, text)

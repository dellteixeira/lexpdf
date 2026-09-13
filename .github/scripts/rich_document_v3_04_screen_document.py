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
rich_methods = r'''

  Future<void> _loadRichDocument(
    String pageId,
    List<NotebookObject> legacyObjects,
  ) async {
    if (_richDocumentPageId == pageId && _richDocument != null) return;

    await _persistRichDocumentNow();
    _richDocumentSaveTimer?.cancel();
    final previous = _richDocument;
    previous?.removeListener(_onRichDocumentChanged);

    final stored = await _documentStore.read(pageId);
    late final FluentDocument document;
    late final bool migratedLegacyText;
    if (stored != null) {
      document = FluentDocument.fromJson(
        jsonDecode(stored.documentJson) as Map<String, dynamic>,
      );
      migratedLegacyText = stored.migratedLegacyText;
    } else {
      document = FluentDocument(
        content: _legacyTextMigrator.migrate(legacyObjects),
      );
      document.pendingFontFamily = _defaultNotebookFontFamily;
      document.pendingFontSize = _defaultNotebookFontSize;
      document.pendingTextAlign = NotebookTextAlign.left.dbValue;
      migratedLegacyText = true;
      await _documentStore.upsert(
        pageId: pageId,
        documentJson: document.toJson(),
        migratedLegacyText: migratedLegacyText,
      );
    }

    _richDocument = document;
    _richDocumentPageId = pageId;
    _richDocumentMigratedLegacyText = migratedLegacyText;
    _lastDocumentContentVersion = document.contentVersion;
    _syncRibbonStateFromDocument(document);
    document.addListener(_onRichDocumentChanged);

    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _onRichDocumentChanged() {
    final document = _richDocument;
    if (document == null) return;

    final ribbonChanged = _syncRibbonStateFromDocument(document);
    if (document.contentVersion != _lastDocumentContentVersion) {
      _lastDocumentContentVersion = document.contentVersion;
      _richDocumentSaveTimer?.cancel();
      _richDocumentSaveTimer = Timer(
        _documentAutosaveDelay,
        () => unawaited(_persistRichDocumentNow()),
      );
    }
    if (ribbonChanged && mounted) setState(() {});
  }

  bool _syncRibbonStateFromDocument(FluentDocument document) {
    final bold = document.pendingStyles.contains('bold');
    final italic = document.pendingStyles.contains('italic');
    final underline = document.pendingStyles.contains('underline');
    final align = NotebookTextAlign.fromDb(document.pendingTextAlign);
    final color = _documentColorValue(document.pendingColor);
    final changed = _defaultTextFontFamily != document.pendingFontFamily ||
        _defaultTextFontSize != document.pendingFontSize ||
        _defaultTextBold != bold ||
        _defaultTextItalic != italic ||
        _defaultTextUnderline != underline ||
        _defaultTextAlign != align ||
        _defaultTextColorValue != color;
    _defaultTextFontFamily = document.pendingFontFamily;
    _defaultTextFontSize = document.pendingFontSize;
    _defaultTextBold = bold;
    _defaultTextItalic = italic;
    _defaultTextUnderline = underline;
    _defaultTextAlign = align;
    _defaultTextColorValue = color;
    return changed;
  }

  int _documentColorValue(String? cssColor) {
    final value = cssColor?.trim();
    if (value == null || value.isEmpty || !value.startsWith('#')) {
      return 0xFF000000;
    }
    final hex = value.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return 0xFF000000;
    if (hex.length == 6) return 0xFF000000 | parsed;
    if (hex.length == 8) return parsed;
    return 0xFF000000;
  }

  String _cssColor(int value) =>
      '#${(value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _persistRichDocumentNow() async {
    final document = _richDocument;
    final pageId = _richDocumentPageId;
    if (document == null || pageId == null) return;
    await _documentStore.upsert(
      pageId: pageId,
      documentJson: document.toJson(),
      migratedLegacyText: _richDocumentMigratedLegacyText,
    );
  }
'''
text = replace_once(text, '''  List<InkStroke> _snapshotStrokes() {''', rich_methods + '''

  List<InkStroke> _snapshotStrokes() {''', 'insert rich document lifecycle')
text = sub_once(text, r"  int get _wordCount \{.*?\n  \}\n\n  Widget _buildViewRibbon", '''  int get _wordCount {
    final combined = _richDocument?.content.text.trim() ?? '';
    if (combined.isEmpty) return 0;
    return RegExp(r'\\S+').allMatches(combined).length;
  }

  Widget _buildViewRibbon''', 'word count from rich document', re.S)
text = replace_once(text, '''            showDocumentRuler: _showDocumentRuler,
            onNewNotebook: () => unawaited(_createNotebook()),''', '''            showDocumentRuler: _showDocumentRuler,
            onOpenDocument: () => unawaited(_openRichDocumentFile()),
            onSaveDocx: () => unawaited(_saveRichDocumentAs('docx')),
            onSaveTxt: () => unawaited(_saveRichDocumentAs('txt')),
            onExportPdf: () => unawaited(_saveRichDocumentAs('pdf')),
            onSaveDoc: () => unawaited(_saveRichDocumentAs('doc')),
            onSaveRtf: () => unawaited(_saveRichDocumentAs('rtf')),
            onRibbonTabChanged: (tab) {
              if (tab == NotebookRibbonTab.home) _activateTextMode();
              if (tab == NotebookRibbonTab.drawing) {
                setState(() => _textMode = false);
              }
            },
            onNewNotebook: () => unawaited(_createNotebook()),''', 'wire document file actions')
text = replace_once(text, '''            onUndo: _history.canUndo ? () => unawaited(_undoHistory()) : null,
            onRedo: _history.canRedo ? () => unawaited(_redoHistory()) : null,''', '''            onUndo: _textMode
                ? () => _richDocument?.undo()
                : (_history.canUndo ? () => unawaited(_undoHistory()) : null),
            onRedo: _textMode
                ? () => _richDocument?.redo()
                : (_history.canRedo ? () => unawaited(_redoHistory()) : null),''', 'text-aware title undo redo')
write(path, text)

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

path = 'apps/lexpdf_app/lib/src/widgets/notebook_wordpad_chrome.dart'
text = read(path)
text = replace_once(
    text,
    '''enum _NotebookFileAction {
  newNotebook,
  renameNotebook,
  deleteNotebook,
  newPage,
  duplicatePage,
  deletePage,
}''',
    '''enum _NotebookFileAction {
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
}''',
    'extend file action enum',
)
text = replace_once(
    text,
    '''    required this.showDocumentRuler,
    required this.onNewNotebook,''',
    '''    required this.showDocumentRuler,
    required this.onOpenDocument,
    required this.onSaveDocx,
    required this.onSaveTxt,
    required this.onExportPdf,
    required this.onSaveDoc,
    required this.onSaveRtf,
    required this.onNewNotebook,''',
    'add file callbacks constructor',
)
text = text.replace(
    '''    required this.onFitPage,
    super.key,''',
    '''    required this.onFitPage,
    this.onRibbonTabChanged,
    super.key,''',
    1,
)
text = replace_once(
    text,
    '''  final bool showDocumentRuler;
  final VoidCallback onNewNotebook;''',
    '''  final bool showDocumentRuler;
  final VoidCallback onOpenDocument;
  final VoidCallback onSaveDocx;
  final VoidCallback onSaveTxt;
  final VoidCallback onExportPdf;
  final VoidCallback onSaveDoc;
  final VoidCallback onSaveRtf;
  final VoidCallback onNewNotebook;''',
    'add file callback fields',
)
text = replace_once(
    text,
    '''  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onFitPage;

  @override''',
    '''  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onFitPage;
  final ValueChanged<NotebookRibbonTab>? onRibbonTabChanged;

  @override''',
    'add ribbon tab field',
)
text = replace_once(
    text,
    '''            activeTab: _tab,
            onTabChanged: (value) => setState(() => _tab = value),''',
    '''            activeTab: _tab,
            onTabChanged: (value) {
              setState(() => _tab = value);
              widget.onRibbonTabChanged?.call(value);
            },''',
    'forward ribbon tab changes',
)
text = replace_once(
    text,
    '''    switch (action) {
      case _NotebookFileAction.newNotebook:''',
    '''    switch (action) {
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
      case _NotebookFileAction.newNotebook:''',
    'handle document file actions',
)
menu_anchor = '''            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _NotebookFileAction.newNotebook,'''
menu_replacement = '''            itemBuilder: (_) => [
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
                value: _NotebookFileAction.newNotebook,'''
text = replace_once(text, menu_anchor, menu_replacement, 'insert document file menu')
write(path, text)

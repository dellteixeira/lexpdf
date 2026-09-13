from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(rel, text):
    (ROOT / rel).write_text(text, encoding='utf-8')

write('apps/lexpdf_app/test/notebook_rich_text_contract_test.dart', r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook uses one FluentDocument flow instead of text boxes', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart').readAsStringSync();
    final surface = File('lib/src/widgets/notebook_rich_document_surface.dart').readAsStringSync();
    expect(screen, contains('FluentDocument? _richDocument'));
    expect(screen, contains('NotebookRichDocumentSurface('));
    expect(screen, contains('_textMode = true'));
    expect(screen, contains('object.type != NotebookObjectType.text'));
    expect(screen, contains('Duration(milliseconds: 650)'));
    expect(screen, contains('document.contentVersion'));
    expect(screen, contains('_legacyTextMigrator.migrate(legacyObjects)'));
    expect(surface, contains('FluentDocumentWidget('));
    expect(surface, contains('FluentToolbarMode.bubble'));
    expect(surface, contains('ThemeData.light'));
    expect(objectLayer, isNot(contains('_InlineNotebookTextEditor')));
    expect(objectLayer, isNot(contains('TextField(')));
  });

  test('notebook rich document persists in schema v11 SQLCipher database', () {
    final db = File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final store = File('lib/src/core/storage/local_notebook_document_store.dart').readAsStringSync();
    expect(db, contains('schemaVersion = 11'));
    expect(db, contains('CREATE TABLE notebook_page_documents'));
    expect(db, contains('document_json TEXT NOT NULL'));
    expect(db, contains('migrated_legacy_text INTEGER NOT NULL'));
    expect(store, contains('class LocalNotebookDocumentStore'));
    expect(store, contains('documentJson: source.documentJson'));
  });

  test('schema v11 document migration stays inside _migrate', () {
    final db = File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final migrateStart = db.indexOf('void _migrate()');
    final migrateEnd = db.indexOf('void close() => database.dispose();');
    final documentMigration = db.indexOf('if (version < 11)');
    final documentTable = db.indexOf('CREATE TABLE notebook_page_documents');
    expect(migrateStart, greaterThanOrEqualTo(0));
    expect(migrateEnd, greaterThan(migrateStart));
    expect(documentMigration, greaterThan(migrateStart));
    expect(documentMigration, lessThan(migrateEnd));
    expect(documentTable, greaterThan(documentMigration));
    expect(documentTable, lessThan(migrateEnd));
  });
}
''')

write('apps/lexpdf_app/test/notebook_text_input_contract_test.dart', r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook text input is a flowing rich document on the paper', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart').readAsStringSync();
    final surface = File('lib/src/widgets/notebook_rich_document_surface.dart').readAsStringSync();
    expect(screen, contains('void _activateTextMode()'));
    expect(screen, contains('document.requestEditorFocus()'));
    expect(screen, contains('NotebookRichDocumentSurface('));
    expect(screen, contains('enabled: _textMode && !_handMode'));
    expect(screen, isNot(contains('_editingTextObjectId')));
    expect(surface, contains('FluentDocumentWidget('));
    expect(surface, contains('onSurface: Color(0xFF202124)'));
    expect(objectLayer, isNot(contains('_InlineNotebookTextEditor')));
    expect(objectLayer, isNot(contains('TextField(')));
  });
}
''')

write('apps/lexpdf_app/test/notebook_wordpad_editor_contract_test.dart', r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WordPad ribbon controls FluentDocument formatting by selection', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    expect(screen, contains("_defaultNotebookFontFamily = 'Arial'"));
    expect(screen, contains('_defaultNotebookFontSize = 12'));
    expect(screen, contains('_buildTextFormattingToolbar(),'));
    expect(screen, contains('document.eventHandler.handleBold()'));
    expect(screen, contains('document.eventHandler.handleItalic()'));
    expect(screen, contains('document.eventHandler.handleUnderline()'));
    expect(screen, contains('document.eventHandler.handleFontFamily'));
    expect(screen, contains('document.eventHandler.handleFontSize'));
    expect(screen, contains('document.eventHandler.handleTextAlign'));
    expect(screen, contains('document.eventHandler.handleTextColor'));
  });

  test('Arquivo menu exposes real document import and export routes', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart').readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart').readAsStringSync();
    final service = File('lib/src/core/notebook/notebook_document_file_service.dart').readAsStringSync();
    expect(chrome, contains("label: 'Abrir documento'"));
    expect(chrome, contains("label: 'Salvar como DOCX'"));
    expect(chrome, contains("label: 'Salvar como TXT'"));
    expect(chrome, contains("label: 'Exportar PDF'"));
    expect(chrome, contains("label: 'Salvar como DOC'"));
    expect(chrome, contains("label: 'Salvar como RTF'"));
    expect(screen, contains('_openRichDocumentFile()'));
    expect(screen, contains("_saveRichDocumentAs('docx')"));
    expect(service, contains("case 'docx':"));
    expect(service, contains("case 'txt':"));
    expect(service, contains("case 'pdf':"));
    expect(service, contains('LegacyWordBridgeUnavailable'));
  });
}
''')

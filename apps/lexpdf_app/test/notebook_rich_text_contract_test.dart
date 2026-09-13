import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook uses one FluentDocument flow instead of text boxes', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final objectLayer = File('lib/src/widgets/notebook_object_layer.dart')
        .readAsStringSync();
    final surface = File('lib/src/widgets/notebook_rich_document_surface.dart')
        .readAsStringSync();
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
    final db = File('lib/src/core/storage/local_database.dart')
        .readAsStringSync();
    final store = File(
      'lib/src/core/storage/local_notebook_document_store.dart',
    ).readAsStringSync();
    expect(db, contains('schemaVersion = 11'));
    expect(db, contains('CREATE TABLE notebook_page_documents'));
    expect(db, contains('document_json TEXT NOT NULL'));
    expect(db, contains('migrated_legacy_text INTEGER NOT NULL'));
    expect(store, contains('class LocalNotebookDocumentStore'));
    expect(store, contains('documentJson: source.documentJson'));
  });

  test('schema v11 document migration stays inside _migrate', () {
    final db = File('lib/src/core/storage/local_database.dart')
        .readAsStringSync();
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

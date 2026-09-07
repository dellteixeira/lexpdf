import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/backup/lex_backup_service.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';

void main() {
  test('creates and validates portable LexPDF backup data', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    await ink.ensureDefaultPage();

    final service = LexBackupService(db);
    final backup = await service.createBackup();
    final validation = await service.validate(backup);

    expect(validation.valid, isTrue);
    expect(validation.format, 'lexbackup');
    expect(validation.version, LexBackupService.formatVersion);
    expect(validation.tableCount, greaterThan(0));
  });

  test('restores database state and bundled offline document', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final temp = await Directory.systemTemp.createTemp('lexpdf-backup-test-');
    addTearDown(() => temp.delete(recursive: true));

    final pdf = File('${temp.path}${Platform.pathSeparator}source.pdf');
    await pdf.writeAsBytes(const [37, 80, 68, 70, 45, 49, 46, 55]);
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      '''INSERT INTO documents(
        id, title, filename, local_path, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?);''',
      ['doc-1', 'Original', 'source.pdf', pdf.path, now, now],
    );

    final service = LexBackupService(db);
    final backup = await service.createBackup();
    db.database.execute("UPDATE documents SET title = 'Mutated' WHERE id = 'doc-1';");

    final restoreDir = Directory('${temp.path}${Platform.pathSeparator}restore');
    await service.restore(backup, documentDirectory: restoreDir);

    final row = db.database.select("SELECT title, local_path FROM documents WHERE id = 'doc-1';").single;
    expect(row['title'], 'Original');
    final restored = File(row['local_path'] as String);
    expect(await restored.exists(), isTrue);
    expect(await restored.readAsBytes(), const [37, 80, 68, 70, 45, 49, 46, 55]);
  });

  test('exports validates and imports .lexnote without overwriting source', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    await ink.ensureDefaultPage();
    final notebooksBefore = await ink.listNotebooks();
    expect(notebooksBefore, isNotEmpty);

    final service = LexBackupService(db);
    final note = service.exportNotebook(notebooksBefore.first.id);
    final validation = service.validateNotebook(note);

    expect(validation.valid, isTrue);
    expect(validation.version, LexBackupService.lexNoteVersion);
    expect(validation.pageCount, greaterThan(0));
    expect(validation.layerCount, greaterThan(0));

    final imported = service.importNotebook(note);
    expect(imported.notebookId, isNot(notebooksBefore.first.id));
    expect(imported.pageCount, validation.pageCount);

    final notebookCount = db.database.select('SELECT COUNT(*) AS total FROM notebooks;').single['total'] as int;
    expect(notebookCount, notebooksBefore.length + 1);
    expect(
      db.database.select('PRAGMA foreign_key_check;'),
      isEmpty,
    );
  });

  test('rejects corrupted backups and corrupted lexnote envelopes', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    await ink.ensureDefaultPage();
    final notebook = (await ink.listNotebooks()).first;
    final service = LexBackupService(db);

    final backupValidation = await service.validate([1, 2, 3, 4]);
    expect(backupValidation.valid, isFalse);

    final note = service.exportNotebook(notebook.id);
    final corrupted = [...note];
    corrupted[corrupted.length ~/ 2] ^= 1;
    expect(service.validateNotebook(corrupted).valid, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/backup/lex_backup_service.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';

void main() {
  test('creates validates and exports portable LexPDF data', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    await ink.ensureDefaultPage();
    final notebooks = await ink.listNotebooks();
    expect(notebooks, isNotEmpty);

    final service = LexBackupService(db);
    final backup = await service.createBackup();
    final validation = await service.validate(backup);
    expect(validation.valid, isTrue);
    expect(validation.format, 'lexbackup');
    expect(validation.tableCount, greaterThan(0));

    final note = service.exportNotebook(notebooks.first.id);
    expect(note, isNotEmpty);
    expect(String.fromCharCodes(note), contains('"format":"lexnote"'));
  });

  test('rejects corrupted backups before restore', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final service = LexBackupService(db);
    final validation = await service.validate([1, 2, 3, 4]);
    expect(validation.valid, isFalse);
  });
}

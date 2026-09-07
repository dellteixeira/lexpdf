import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/local_document_provider.dart';
import 'package:lexpdf_app/src/core/documents/local_library_indexer.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';

void main() {
  test('indexes only PDFs from a local directory into SQLite', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf_indexer_');
    addTearDown(() => directory.delete(recursive: true));

    await File('${directory.path}${Platform.pathSeparator}A.pdf').writeAsBytes([1, 2, 3]);
    await File('${directory.path}${Platform.pathSeparator}B.PDF').writeAsBytes([4, 5, 6]);
    await File('${directory.path}${Platform.pathSeparator}notes.txt').writeAsString('ignore');

    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final indexer = LocalLibraryIndexer(
      provider: const LocalDocumentProvider(),
      catalog: catalog,
    );

    final indexed = await indexer.indexDirectory(directory.path);
    expect(indexed, hasLength(2));

    final persisted = await catalog.list();
    expect(persisted.map((document) => document.name).toSet(), {'A.pdf', 'B.PDF'});
  });
}

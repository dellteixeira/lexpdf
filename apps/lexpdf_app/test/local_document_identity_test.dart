import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/documents/local_document_identity.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';

void main() {
  test('local identity remains stable across file rename', () async {
    final dir = await Directory.systemTemp.createTemp('lexpdf-identity-');
    addTearDown(() => dir.delete(recursive: true));

    final first = File('${dir.path}${Platform.pathSeparator}original.pdf');
    await first.writeAsBytes(List<int>.generate(220000, (i) => i % 251));
    final second = File('${dir.path}${Platform.pathSeparator}renamed.pdf');
    await first.rename(second.path);

    const identity = LocalDocumentIdentity();
    final a = await identity.identifyLocal(
      path: second.path,
      name: 'renamed.pdf',
    );
    final copied = File('${dir.path}${Platform.pathSeparator}moved.pdf');
    await second.copy(copied.path);
    final b = await identity.identifyLocal(
      path: copied.path,
      name: 'moved.pdf',
    );

    expect(a.id, b.id);
    expect(a.id, startsWith(LocalDocumentIdentity.idPrefix));
  });

  test('catalog alias preserves a legacy document id and its foreign-key state', () async {
    final dir = await Directory.systemTemp.createTemp('lexpdf-alias-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}law.pdf');
    await file.writeAsBytes(List<int>.generate(200000, (i) => (i * 7) % 253));

    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final catalog = LocalDocumentCatalog(db);
    final legacyId = file.path;
    await catalog.upsert(DocumentRef(
      id: legacyId,
      name: 'law.pdf',
      provider: DocumentProviderKind.local,
      localPath: file.path,
      availableOffline: true,
    ));

    const identity = LocalDocumentIdentity();
    final identified = await identity.identifyLocal(
      path: file.path,
      name: 'law.pdf',
    );
    final resolved = await catalog.resolveLocalDocument(identified);
    expect(resolved.id, legacyId);

    final moved = File('${dir.path}${Platform.pathSeparator}law-renamed.pdf');
    await file.rename(moved.path);
    final renamed = await identity.identifyLocal(
      path: moved.path,
      name: 'law-renamed.pdf',
    );
    final resolvedAfterRename = await catalog.resolveLocalDocument(renamed);

    expect(resolvedAfterRename.id, legacyId);
    expect(resolvedAfterRename.localPath, moved.path);
  });
}

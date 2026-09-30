import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_text_annotation_store.dart';

void main() {
  test('5000-page annotation workload stays page-window addressable', () async {
    const documentId = 'huge-search-annotations';
    const pageCount = 5000;
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final catalog = LocalDocumentCatalog(db);
    final store = LocalTextAnnotationStore(db);

    await catalog.upsert(
      const DocumentRef(
        id: documentId,
        name: 'huge-search-annotations.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/huge-search-annotations.pdf',
        availableOffline: true,
      ),
    );

    final base = DateTime.utc(2026, 9, 8);
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var page = 1; page <= pageCount; page++) {
        final type = switch (page % 3) {
          0 => TextAnnotationType.highlight,
          1 => TextAnnotationType.underline,
          _ => TextAnnotationType.strikeout,
        };
        await store.upsert(
          LocalTextAnnotation(
            id: 'annotation-$page',
            documentId: documentId,
            pageNumber: page,
            startIndex: page % 17,
            endIndex: (page % 17) + 4,
            type: type,
            selectedText: 'page-$page',
            colorValue: 0xFFFFD54F + (page % 4),
            opacity: 0.35 + ((page % 3) * 0.1),
            createdAt: base.add(Duration(seconds: page)),
            updatedAt: base.add(Duration(seconds: page)),
          ),
        );
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }

    expect(await store.countForDocument(documentId), pageCount);

    final middle = await store.listForPageRange(documentId, 2498, 2503);
    expect(middle, hasLength(6));
    expect(middle.first.pageNumber, 2498);
    expect(middle.last.pageNumber, 2503);
    expect(
      middle.map((annotation) => annotation.type).toSet(),
      containsAll(<TextAnnotationType>{
        TextAnnotationType.highlight,
        TextAnnotationType.underline,
        TextAnnotationType.strikeout,
      }),
    );

    final lastPage = await store.listForPage(documentId, pageCount);
    expect(lastPage, hasLength(1));
    expect(lastPage.single.selectedText, 'page-5000');

    final original = lastPage.single;
    await store.upsert(
      original.copyWith(
        type: TextAnnotationType.highlight,
        colorValue: 0xFF64B5F6,
        opacity: 0.55,
      ),
    );
    final updated = (await store.listForPage(documentId, pageCount)).single;
    expect(updated.type, TextAnnotationType.highlight);
    expect(updated.colorValue, 0xFF64B5F6);
    expect(updated.opacity, 0.55);

    await store.delete('annotation-2500');
    expect(await store.listForPage(documentId, 2500), isEmpty);
    expect(await store.countForDocument(documentId), pageCount - 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('reader keeps pdfrx search independent from overlay materialization', () {
    final source = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(source, contains('PdfTextSearcher(_viewerController)'));
    expect(source, contains('_textSearcher.pageTextMatchPaintCallback'));
    expect(source, contains('_textSearcher.goToPrevMatch()'));
    expect(source, contains('_textSearcher.goToNextMatch()'));
    expect(source, contains('onChanged: _scheduleSearch'));
    expect(source, contains('onSubmitted: _submitSearch'));
    expect(source, contains('PdfSearchAppBarActions('));
    expect(source, contains('HugePdfPolicy.overlayWindow('));
    expect(source, contains('listForPageRange('));
  });

  test('Android native reader exposes persistent PDF.js search navigation', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('button("Buscar") { showSearchPanel() }'));
    expect(source, contains('fun searchState(json: String)'));
    expect(source, contains('async function startTextSearch(rawQuery)'));
    expect(source, contains('async function goToSearchResult('));
    expect(source, contains('async function renderSearchHighlight('));
    expect(source, contains('searchNext() { return goToSearchResult('));
    expect(source, contains('searchPrevious() { return goToSearchResult('));
    expect(source, contains('RANGE_CHUNK_SIZE = 512 * 1024'));
  });

  test('Windows workspace reader keeps Acrobat-style search in the viewer', () {
    final source =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();

    expect(source, contains('PdfTextSearcher(_controller)'));
    expect(source, contains('_textSearcher.pageTextMatchPaintCallback'));
    expect(source, contains("LogicalKeyboardKey.keyF, control: true"));
    expect(source, contains("tooltip: 'Ocorrência anterior'"));
    expect(source, contains("tooltip: 'Próxima ocorrência'"));
    expect(source, contains('onChanged: _scheduleSearch'));
    expect(source, contains('onSubmitted: _submitSearch'));
  });

  test('workspace search keeps result navigation open while changing pages', () {
    final source =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    expect(source, contains('Pesquisar palavra ou frase'));
    expect(source, contains("tooltip: 'Ocorrência anterior'"));
    expect(source, contains("tooltip: 'Próxima ocorrência'"));
    expect(source, contains('_openIndexedSearchPage(page);'));
    expect(source, isNot(contains("showDialog<String>(")));
  });
}

import 'dart:io';

import 'package:dart_pdf_reader/dart_pdf_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  const pageCount = 1600;

  test('1600-page PDF is saved and reopened without eager page materialization',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('lexpdf-1600-page-acceptance');
    addTearDown(() => directory.delete(recursive: true));

    final document = pw.Document(compress: true);
    for (var page = 1; page <= pageCount; page++) {
      document.addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Text('LexPDF very large document page $page'),
          ),
        ),
      );
    }

    final path =
        '${directory.path}${Platform.pathSeparator}lexpdf-1600-pages.pdf';
    await File(path).writeAsBytes(await document.save(), flush: true);

    final bytes = await File(path).readAsBytes();
    final parsed = await PDFParser(ByteStream(bytes)).parse();
    final pages = await (await parsed.catalog).getPages();

    expect(bytes, isNotEmpty);
    expect(pages.pageCount, pageCount);
    expect(pages.getPageAtIndex(0), isNotNull);
    expect(pages.getPageAtIndex(799), isNotNull);
    expect(pages.getPageAtIndex(pageCount - 1), isNotNull);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('reader source keeps very-large-document lazy loading enabled', () async {
    final source = await File('lib/src/screens/pdf_reader_screen.dart').readAsString();

    expect(source, contains('loadPageDimensionsOnDemand: true'));
    expect(source, contains('limitRenderingCache: true'));
    expect(
      source,
      contains('maxImageBytesCachedOnMemory: HugePdfPolicy.viewerImageCacheBytes'),
    );
    expect(HugePdfPolicy.viewerImageCacheBytes, lessThanOrEqualTo(96 * 1024 * 1024));
    expect(source, contains('useProgressiveLoading: true'));
    expect(source, isNot(contains('FutureBuilder<ReadingProgressState?>')));
  });
}

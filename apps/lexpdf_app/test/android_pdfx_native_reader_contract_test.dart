import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native reader is backed by pdfx and not pdfrx', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final reader = File(
      'lib/src/screens/android_native_pdf_reader_screen.dart',
    ).readAsStringSync();

    expect(pubspec, contains('pdfx: 2.11.0'));
    expect(reader, contains("import 'package:pdfx/pdfx.dart';"));
    expect(reader, isNot(contains("import 'package:pdfrx/pdfrx.dart';")));
    expect(reader, contains('PdfDocument.openFile(path)'));
    expect(reader, contains('PdfController('));
    expect(reader, contains('PdfView('));
  });

  test('Android workspace routes to native reader before desktop pdfrx editor', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();

    final nativeReader = workspace.indexOf('AndroidNativePdfReaderScreen(');
    final desktopEditor = workspace.indexOf('return editor.PdfWorkspaceScreen(');

    expect(workspace, contains("import 'android_native_pdf_reader_screen.dart';"));
    expect(workspace, contains('if (Platform.isAndroid)'));
    expect(nativeReader, greaterThanOrEqualTo(0));
    expect(desktopEditor, greaterThan(nativeReader));
    expect(workspace, contains('No pdfrx/PDFium viewer is mounted on this platform.'));
  });

  test('Android app bootstrap does not initialize pdfrx/PDFium', () {
    final main = File('lib/main.dart').readAsStringSync();
    final normalized = main.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      normalized,
      contains('if (Platform.isWindows) { await pdfrxFlutterInitialize(); }'),
    );
    expect(
      normalized,
      isNot(contains(
        'Future<_BootstrapData> _initialize() async { await pdfrxFlutterInitialize();',
      )),
    );
  });

  test('Android native reader keeps opening path free of OCR and indexing', () {
    final reader = File(
      'lib/src/screens/android_native_pdf_reader_screen.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();

    expect(reader, isNot(contains('MobilePdfOcrService')));
    expect(reader, isNot(contains('PdfTextSearcher')));
    expect(reader, isNot(contains('loadOutline')));
    expect(reader, isNot(contains('LocalTextAnnotationStore')));
    expect(
      workspace,
      contains(
        'Indexação/OCR está desativada no novo leitor nativo Android',
      ),
    );
  });

  test('native safe reader preserves page navigation and reading position', () {
    final reader = File(
      'lib/src/screens/android_native_pdf_reader_screen.dart',
    ).readAsStringSync();

    expect(reader, contains('initialPage: _page'));
    expect(reader, contains('onPageChanged: (page)'));
    expect(reader, contains('widget.onPageChanged(page)'));
    expect(reader, contains('previousPage('));
    expect(reader, contains('nextPage('));
    expect(reader, contains('scrollDirection: Axis.vertical'));
    expect(reader, contains('pageSnapping: true'));
  });
}

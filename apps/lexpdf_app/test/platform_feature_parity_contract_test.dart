import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/native_pdf_open_service.dart';

void main() {
  test('native PDF startup accepts paths with spaces and Unicode', () {
    expect(
      NativePdfOpenService.pdfPathFromArgs(
        const ['--ignored', r'C:\Estudos\Direito Constitucional\ação civil.pdf'],
      ),
      r'C:\Estudos\Direito Constitucional\ação civil.pdf',
    );
    expect(
      NativePdfOpenService.pdfPathFromArgs(
        const ['/storage/emulated/0/Estudos/Constituição Federal.PDF'],
      ),
      '/storage/emulated/0/Estudos/Constituição Federal.PDF',
    );
    expect(
      NativePdfOpenService.pdfPathFromArgs(const ['notes.txt']),
      isNull,
    );
  });

  test('all supported native entry paths converge on the unified Flutter PDF workspace', () {
    final android = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final windows = File('windows/runner/main.cpp').readAsStringSync();
    final mainDart = File('lib/main.dart').readAsStringSync();
    final app = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(android, contains('lexpdf/native_pdf_open'));
    expect(android, contains('invokeMethod("openPdfPath", path)'));
    expect(windows, contains('set_dart_entrypoint_arguments'));
    expect(mainDart, contains('NativePdfOpenService.pdfPathFromArgs(args)'));
    expect(app, contains('Future<void> _openNativePdf(String path)'));
    expect(app, contains('PdfWorkspaceScreen('));
    expect(app, isNot(contains('PdfReaderScreen(')));
  });

  test('reader parity keeps search, text annotations and ink in common code', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();
    final annotations = File(
      'lib/src/core/storage/local_text_annotation_store.dart',
    ).readAsStringSync();
    final ink = File(
      'lib/src/core/storage/local_pdf_ink_store.dart',
    ).readAsStringSync();

    expect(reader, contains('PdfTextSearcher'));
    expect(reader, contains('LocalTextAnnotationStore'));
    expect(reader, contains('LocalPdfInkStore'));
    expect(annotations, contains('TextAnnotationType.highlight'));
    expect(annotations, contains('TextAnnotationType.underline'));
    expect(annotations, contains('TextAnnotationType.strikeout'));
    expect(annotations, contains('listForPageRange'));
    expect(ink, contains('listForPageRange'));
    expect(ink, contains('replaceStrokeWithFragments'));
  });

  test('library parity keeps notebooks and offline catalog available', () {
    final library = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();
    final catalog = File(
      'lib/src/core/storage/local_document_catalog.dart',
    ).readAsStringSync();

    expect(library, contains('NotebookScreen'));
    expect(library, contains('_HomeSection.notebooks'));
    expect(library, contains('_HomeSection.offline'));
    expect(library, contains('document.hasLocalPath'));
    expect(catalog, contains('is_available_offline'));
    expect(catalog, contains('availableOffline:'));
    expect(catalog, contains('markOpened'));
  });

  test('persistence contracts remain platform-neutral SQLite stores', () {
    final database = File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final progress = File(
      'lib/src/core/storage/local_reading_progress_store.dart',
    ).readAsStringSync();

    expect(database, contains('class LocalDatabase'));
    expect(progress, contains('class LocalReadingProgressStore'));
    expect(progress, isNot(contains('Platform.isAndroid')));
    expect(progress, isNot(contains('Platform.isWindows')));
  });

  test('Windows release executes the shared parity suite before build', () {
    final workflow = File('../../.github/workflows/release-hardening.yml')
        .readAsStringSync();
    const step = 'Run platform feature parity contracts';
    const command = 'flutter test test/platform_feature_parity_contract_test.dart';

    expect(step.allMatches(workflow).length, 1);
    expect(command.allMatches(workflow).length, 1);
    expect(
      workflow.indexOf(command),
      lessThan(workflow.indexOf('Build Windows release')),
    );
  });
}

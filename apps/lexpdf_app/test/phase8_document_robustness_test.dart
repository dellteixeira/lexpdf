import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/pdf_document_robustness_service.dart';
import 'package:lexpdf_app/src/core/pdf/pdf_file_preflight.dart';

void main() {
  late Directory tempDir;
  const service = PdfDocumentRobustnessService();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lexpdf-phase8-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('async preflight rejects missing and invalid local PDFs', () async {
    final missing = await PdfFilePreflight.inspect('${tempDir.path}/missing.pdf');
    expect(missing.canOpen, isFalse);
    expect(missing.errorMessage, contains('não foi encontrado'));

    final invalid = File('${tempDir.path}/invalid.pdf')
      ..writeAsStringSync('this is not a pdf');
    final invalidResult = await PdfFilePreflight.inspect(invalid.path);
    expect(invalidResult.canOpen, isFalse);
    expect(invalidResult.errorMessage, contains('cabeçalho PDF válido'));
  });

  test('bounded inspection accepts Unicode paths and reports incomplete tail', () async {
    final folder = Directory('${tempDir.path}/Constituição_日本語')..createSync();
    final file = File('${folder.path}/lei ç.pdf')
      ..writeAsStringSync('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n');

    final report = await service.inspect(file.path);

    expect(report.canOpen, isTrue);
    expect(report.unicodePath, isTrue);
    expect(report.hasPdfHeader, isTrue);
    expect(report.hasEofMarker, isFalse);
    expect(report.warnings.join(' '), contains('marcador final'));
  });

  test('detects encryption hint without reading the full document', () async {
    final file = File('${tempDir.path}/protected.pdf')
      ..writeAsStringSync(
        '%PDF-1.7\n1 0 obj\n<< /Encrypt 8 0 R /Filter /Standard >>\nendobj\n%%EOF',
      );

    final result = await PdfFilePreflight.inspect(file.path);

    expect(result.canOpen, isTrue);
    expect(result.passwordProtected, isTrue);
    expect(result.warningMessages.join(' '), contains('proteção'));
  });

  test('read-only source remains openable and is surfaced as a warning', () async {
    if (Platform.isWindows) return;
    final file = File('${tempDir.path}/read-only.pdf')
      ..writeAsStringSync('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF');
    expect(Process.runSync('chmod', ['444', file.path]).exitCode, 0);
    addTearDown(() {
      if (file.existsSync()) Process.runSync('chmod', ['644', file.path]);
    });

    final result = await PdfFilePreflight.inspect(file.path);

    expect(result.canOpen, isTrue);
    expect(result.readOnly, isTrue);
    expect(result.warningMessages.join(' '), contains('somente leitura'));
  });

  test('runtime failure classifier distinguishes resource and file failures', () {
    expect(
      PdfRuntimeFailureClassifier.classify(Exception('No space left on device')).kind,
      PdfRuntimeFailureKind.diskFull,
    );
    expect(
      PdfRuntimeFailureClassifier.classify(Exception('Out of memory')).kind,
      PdfRuntimeFailureKind.outOfMemory,
    );
    expect(
      PdfRuntimeFailureClassifier.classify(Exception('password required')).kind,
      PdfRuntimeFailureKind.passwordRequired,
    );
    expect(
      PdfRuntimeFailureClassifier.classify(Exception('permission denied')).kind,
      PdfRuntimeFailureKind.permissionDenied,
    );
    expect(
      PdfRuntimeFailureClassifier.classify(Exception('corrupt xref table')).kind,
      PdfRuntimeFailureKind.corruptOrUnsupported,
    );
  });

  test('phase 8 preserves bounded huge-PDF, forms and internal-link paths', () {
    final hugePolicy = File('lib/src/core/pdf/huge_pdf_policy.dart').readAsStringSync();
    final reader = File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final formStore = File('lib/src/core/storage/local_pdf_form_store.dart').readAsStringSync();

    expect(hugePolicy, contains('viewerImageCacheBytes'));
    expect(hugePolicy, contains('ocrMaxPixels'));
    expect(reader, contains('PdfLinkHandlerParams'));
    expect(reader, contains('_goToInternalPdfDestination'));
    expect(reader, contains('PdfFormsScreen'));
    expect(formStore, contains('class LocalPdfFormStore'));
  });
}

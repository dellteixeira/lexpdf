import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/pdf_file_preflight.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lexpdf-preflight-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('accepts a local file with a PDF signature', () {
    final file = File('${tempDir.path}/valid.pdf')
      ..writeAsBytesSync('%PDF-1.7\nbody'.codeUnits);

    final result = PdfFilePreflight.inspectSync(file.path);

    expect(result.canOpen, isTrue);
    expect(result.lengthBytes, file.lengthSync());
    expect(result.errorMessage, isNull);
  });

  test('accepts a PDF signature within the bounded header probe', () {
    final file = File('${tempDir.path}/prefixed.pdf')
      ..writeAsBytesSync([...List<int>.filled(16, 0), ...'%PDF-1.7'.codeUnits]);

    final result = PdfFilePreflight.inspectSync(file.path);

    expect(result.canOpen, isTrue);
  });

  test('rejects a missing local file before opening the viewer', () {
    final result = PdfFilePreflight.inspectSync('${tempDir.path}/missing.pdf');

    expect(result.canOpen, isFalse);
    expect(result.errorMessage, contains('não foi encontrado'));
  });

  test('rejects an empty or truncated file', () {
    final file = File('${tempDir.path}/empty.pdf')..writeAsBytesSync(const []);

    final result = PdfFilePreflight.inspectSync(file.path);

    expect(result.canOpen, isFalse);
    expect(result.errorMessage, contains('vazio ou incompleto'));
  });

  test('rejects non-PDF content without scanning the whole file', () {
    final file = File('${tempDir.path}/invalid.pdf')
      ..writeAsBytesSync(List<int>.filled(4096, 0x41));

    final result = PdfFilePreflight.inspectSync(file.path);

    expect(result.canOpen, isFalse);
    expect(result.lengthBytes, 4096);
    expect(result.errorMessage, contains('cabeçalho PDF válido'));
  });
}

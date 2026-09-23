import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  test('Fernando Pestana regression profile is classified as a large Android PDF', () {
    // Regression profile: A_Gramatica_para_o_Ensino_Superior_2025_Fernando_Pestana.pdf
    // observed in physical-device testing: 1267 pages / 74,325,936 bytes.
    expect(
      HugePdfPolicy.isLargeAndroidPdf(
        pageCount: 1267,
        fileSizeBytes: 74325936,
      ),
      isTrue,
    );
    expect(
      HugePdfPolicy.shouldUseAndroidSafeLocalOpen(
        recoveryLevel: 0,
        fileSizeBytes: 74325936,
      ),
      isTrue,
    );
  });

  test('Android local large/recovery opens disable progressive loading', () {
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(editor, contains('bool get _androidSafeLocalOpen'));
    expect(editor, contains('shouldUseAndroidSafeLocalOpen('));
    expect(
      editor,
      contains('useProgressiveLoading: !_androidSafeLocalOpen'),
    );
    expect(
      HugePdfPolicy.shouldUseAndroidSafeLocalOpen(
        recoveryLevel: 1,
        fileSizeBytes: 1,
      ),
      isTrue,
    );
  });

  test('Android opening window is render-only until the document is stable', () {
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(editor, contains('bool _androidReaderStable = false'));
    expect(editor, contains('bool get _androidMinimalReader'));
    expect(editor, contains('_android && (!_androidReaderStable || _androidRecoveryLevel > 0)'));
    expect(editor, contains('_stableOpenTimer = Timer('));
    expect(editor, contains('HugePdfPolicy.androidStableOpenWindow'));
    expect(editor, contains('setState(() => _androidReaderStable = true)'));
    expect(editor, contains('_androidMinimalReader\n                                ? const <Widget>[]'));
    expect(editor, contains('!_androidMinimalReader &&'));
  });

  test('Android automatic OCR/indexing is disabled; user-triggered indexing remains', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();

    final changedStart = workspace.indexOf('void _onViewerDocumentChanged');
    final inspectStart =
        workspace.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final manualStart =
        workspace.indexOf('Future<void> _startBackgroundIndexing');

    expect(changedStart, greaterThanOrEqualTo(0));
    expect(inspectStart, greaterThan(changedStart));
    expect(manualStart, greaterThan(inspectStart));

    final changedBody = workspace.substring(changedStart, inspectStart);
    expect(changedBody, contains('if (Platform.isAndroid)'));
    expect(changedBody, contains('tab.localizedIndexPending = false'));
    expect(changedBody, contains('return;'));

    final inspectBody = workspace.substring(inspectStart, manualStart);
    expect(inspectBody, contains('if (Platform.isAndroid) return;'));

    final manualBody = workspace.substring(manualStart);
    expect(manualBody, contains('..automatic = false'));
    expect(manualBody, contains('openedDocument: viewerDocument'));
  });

  test('Android OCR raster budget is capped near 1.5 MP without a duplicate PNG copy', () {
    final ocr = File(
      'lib/src/core/ocr/mobile_pdf_ocr_service.dart',
    ).readAsStringSync();

    expect(HugePdfPolicy.ocrMaxPixels, 1500000);
    expect(HugePdfPolicy.ocrMaxDimension, 1600);
    expect(ocr, contains('final png = img.encodePng(rendered.createImageNF());'));
    expect(ocr, isNot(contains('Uint8List.fromList')));
  });

  test('recovery session stays in minimal-reader mode after stability', () {
    final editor = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(
      editor,
      contains('_android && (!_androidReaderStable || _androidRecoveryLevel > 0)'),
    );
    expect(editor, contains('if (_androidRecoveryLevel > 0)'));
    expect(
      editor,
      contains('Recovery mode stays a minimal reader for the whole session'),
    );
  });
}

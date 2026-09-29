import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manual OCR uses the local path without enabling automatic indexing', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    final manualStart =
        workspace.indexOf('Future<void> _startBackgroundIndexing');
    final manualEnd = workspace.indexOf('void _startActiveIndexing', manualStart);
    expect(manualStart, greaterThanOrEqualTo(0));
    expect(manualEnd, greaterThan(manualStart));
    final manualBody = workspace.substring(manualStart, manualEnd);

    expect(manualBody, contains('final androidPath = Platform.isAndroid ? document.localPath : null'));
    expect(manualBody, contains('filePath: androidPath'));
    expect(
      manualBody,
      contains('openedDocument: Platform.isAndroid ? null : viewerDocument'),
    );
    expect(manualBody, contains('..automatic = false'));

    final inspectStart =
        workspace.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final activityStart = workspace.indexOf('void _markReaderActivity', inspectStart);
    final inspectBody = workspace.substring(inspectStart, activityStart);
    expect(inspectBody, contains('if (Platform.isAndroid) return;'));

    final idleStart = workspace.indexOf('void _scheduleIdleIndexContinuation');
    final idleEnd = workspace.indexOf(
      'Future<void> _continueIndexingWhenIdle',
      idleStart,
    );
    expect(
      workspace.substring(idleStart, idleEnd),
      contains('if (Platform.isAndroid) return;'),
    );
  });
}

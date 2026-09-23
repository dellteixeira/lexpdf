import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader reports interaction activity on Android and desktop gestures', () {
    final editor =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();

    expect(editor, contains('final VoidCallback? onReaderActivity;'));
    expect(editor, contains('widget.onReaderActivity?.call();'));
    expect(editor, contains('onFocalPointChanged:'));
    expect(editor, contains('onNavigationEnd: ()'));
    expect(editor, contains('onInteractionStart:'));
    expect(editor, contains('onInteractionUpdate:'));
    expect(editor, contains('onInteractionEnd:'));
    expect(editor, contains('void _onPageChanged(int? pageNumber)'));
  });

  test('automatic indexing pauses on activity and resumes only after idle delay', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final policy =
        File('lib/src/core/pdf/huge_pdf_policy.dart').readAsStringSync();

    expect(workspace, contains('Timer? _idleIndexTimer;'));
    expect(workspace, contains('_markReaderActivity'));
    expect(workspace, contains('_scheduleIdleIndexContinuation'));
    expect(workspace, contains('_continueIndexingWhenIdle'));
    expect(workspace, contains('_startIdleIndexChunk'));
    expect(workspace, contains('task.running && task.automatic'));
    expect(workspace, contains('task.cancelRequested = true'));
    expect(workspace, contains('processedPageState'));
    expect(workspace, contains('HugePdfPolicy.nextIdleIndexWindow'));
    expect(workspace, contains('startPage: startPage'));
    expect(workspace, contains('endPage: endPage'));
    expect(workspace, contains('onReaderActivity: () =>'));
    expect(policy, contains('backgroundIndexIdleDelay'));
    expect(policy, contains('idleIndexChunkPages = 6'));
  });

  test('rendering wins the resource lease before automatic indexing starts', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    expect(workspace, contains('int _readerActivityEpoch = 0;'));
    expect(workspace, contains('DateTime? _lastReaderActivityAt;'));
    expect(workspace, contains('_readerActivityEpoch++;'));
    expect(workspace, contains('scheduledEpoch != _readerActivityEpoch'));
    expect(workspace, contains('quietFor < HugePdfPolicy.backgroundIndexIdleDelay'));
    expect(workspace, contains('localizedIndexPending = true'));
    expect(workspace, contains('_scheduleIdleIndexContinuation(tab)'));

    final inspectStart =
        workspace.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final schedulerStart =
        workspace.indexOf('void _scheduleIdleIndexContinuation', inspectStart);
    final inspectBody = workspace.substring(inspectStart, schedulerStart);
    expect(inspectBody, isNot(contains('_startIdleIndexChunk(')));
  });

  test('explicit full indexing remains distinct from automatic idle chunks', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    final idleStart = workspace.indexOf('Future<bool> _startIdleIndexChunk');
    final fullStart =
        workspace.indexOf('Future<void> _startBackgroundIndexing', idleStart);
    expect(idleStart, greaterThanOrEqualTo(0));
    expect(fullStart, greaterThan(idleStart));

    final idleBody = workspace.substring(idleStart, fullStart);
    expect(idleBody, contains('..automatic = true'));
    expect(idleBody, contains('startPage: startPage'));
    expect(idleBody, contains('endPage: endPage'));
    expect(idleBody, contains('openedDocument: viewerDocument'));
    expect(idleBody, isNot(contains('filePath: path')));

    final fullBody = workspace.substring(fullStart);
    expect(fullBody, contains('..automatic = false'));
    expect(fullBody, contains('resume: true'));
    expect(fullBody, contains('openedDocument: viewerDocument'));
  });
}

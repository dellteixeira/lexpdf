import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/pdf_open_crash_guard.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lexpdf-crash-guard-test');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  PdfOpenCrashGuard guard() => PdfOpenCrashGuard(
        directoryProvider: () async => temp,
      );

  test('first open uses normal profile and an interrupted reopen escalates', () async {
    final service = guard();

    final first = await service.begin('document-a');
    expect(first.recoveryLevel, 0);
    expect(first.hadInterruptedOpen, isFalse);

    final second = await service.begin('document-a');
    expect(second.recoveryLevel, 1);
    expect(second.hadInterruptedOpen, isTrue);

    final third = await service.begin('document-a');
    expect(third.recoveryLevel, 2);
    expect(third.hadInterruptedOpen, isTrue);

    final capped = await service.begin('document-a');
    expect(capped.recoveryLevel, 2);
  });

  test('stable open clears the marker and returns the document to normal', () async {
    final service = guard();

    await service.begin('document-a');
    await service.begin('document-a');
    await service.markStable('document-a');

    final next = await service.begin('document-a');
    expect(next.recoveryLevel, 0);
    expect(next.hadInterruptedOpen, isFalse);
  });

  test('a marker for another document does not penalize the next PDF', () async {
    final service = guard();

    await service.begin('document-a');
    final other = await service.begin('document-b');

    expect(other.recoveryLevel, 0);
    expect(other.hadInterruptedOpen, isFalse);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS materializes Finder PDFs into persistent app support storage', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('.applicationSupportDirectory'));
    expect(source, contains('appendingPathComponent("LexPDF", isDirectory: true)'));
    expect(source, contains('appendingPathComponent("native_open", isDirectory: true)'));
    expect(source, contains('startAccessingSecurityScopedResource()'));
    expect(source, contains('stopAccessingSecurityScopedResource()'));
    expect(source, contains('copyItem(at: sourceUrl, to: temporary)'));
    expect(source, contains('replaceItemAt(target, withItemAt: temporary)'));
    expect(source, contains('moveItem(at: temporary, to: target)'));
  });

  test('macOS native PDF import rejects empty copies and uses stable names', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('size.int64Value > 0'));
    expect(source, contains('stablePathKey(sourceUrl.path)'));
    expect(source, contains('14695981039346656037'));
    expect(source, contains('1099511628211'));
  });

  test('macOS queues multiple Finder PDF opens and delivers sequentially', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('private var pendingPdfPaths: [String] = []'));
    expect(source, contains('pendingPdfPaths.append(contentsOf: paths)'));
    expect(source, contains('private var deliveringPdf = false'));
    expect(source, contains('deliverPendingPdfIfPossible()'));
    expect(source, contains('pendingPdfPaths.removeFirst()'));
    expect(source, contains('channel.invokeMethod("openPdfPath", arguments: path)'));
  });
}

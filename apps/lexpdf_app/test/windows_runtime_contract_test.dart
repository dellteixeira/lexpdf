import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner preserves Unicode file arguments for Dart startup', () {
    final utils = File('windows/runner/utils.cpp').readAsStringSync();
    final main = File('windows/runner/main.cpp').readAsStringSync();

    expect(utils, contains('CommandLineToArgvW'));
    expect(utils, contains('Utf8FromUtf16(argv[i])'));
    expect(utils, contains('WideCharToMultiByte'));
    expect(main, contains('GetCommandLineArguments()'));
    expect(main, contains('set_dart_entrypoint_arguments'));
  });

  test('Windows manifest enables HiDPI and long path awareness', () {
    final manifest = File('windows/runner/runner.exe.manifest').readAsStringSync();

    expect(manifest, contains('PerMonitorV2'));
    expect(manifest, contains('<longPathAware'));
    expect(manifest, contains('>true</longPathAware>'));
  });

  test('Windows native window uses the product name', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();

    expect(main, contains('window.Create(L"LexPDF", origin, size)'));
    expect(main, isNot(contains('window.Create(L"lexpdf_app"')));
  });

  test('Windows startup keeps external PDFs in place for read-only access', () {
    final mainDart = File('lib/main.dart').readAsStringSync();
    final app = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(mainDart, contains('NativePdfOpenService.pdfPathFromArgs(args)'));
    expect(app, contains('File(path)'));
    expect(app, contains('localPath: path'));
    expect(app, isNot(contains('copySync')));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android accepts PDF view/share intents without broad storage access', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android:mimeType="application/pdf"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(activity, contains('File(filesDir, "native_open")'));
    expect(activity, isNot(contains('File(cacheDir, "native_open")')));
    expect(activity, contains('contentResolver.openInputStream(uri)'));
    expect(activity, contains('invokeMethod("openPdfPath", path)'));
  });

  test('Windows forwards command line arguments into Dart startup', () {
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final mainDart = File('lib/main.dart').readAsStringSync();

    expect(runner, contains('GetCommandLineArguments()'));
    expect(runner, contains('set_dart_entrypoint_arguments'));
    expect(mainDart, contains('main(List<String> args)'));
    expect(mainDart, contains('NativePdfOpenService.pdfPathFromArgs(args)'));
    expect(mainDart, contains('initialPdfPath: initialPdfPath'));
  });
}

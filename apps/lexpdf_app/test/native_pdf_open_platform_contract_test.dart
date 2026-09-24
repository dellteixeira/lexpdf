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

  test('Android file picker streams large PDFs without file_selector buffering', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final picker = File(
      'lib/src/core/documents/document_picker_service.dart',
    ).readAsStringSync();

    expect(picker, contains("MethodChannel('lexpdf/native_pdf_picker')"));
    expect(picker, contains('if (Platform.isAndroid)'));
    final androidBranch = picker.substring(
      picker.indexOf('if (Platform.isAndroid)'),
      picker.indexOf('final file = await openFile'),
    );
    expect(androidBranch, isNot(contains('openFile(')));

    expect(activity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(activity, contains('Intent.CATEGORY_OPENABLE'));
    expect(activity, contains('contentResolver.openInputStream(uri)'));
    expect(activity, contains('Thread('));
    expect(activity, contains('"LexPdfPickerCopy"'));
    expect(activity, contains('"LexPdfIntentCopy"'));
    expect(
      activity,
      contains('input.copyTo(output, bufferSize = 64 * 1024)'),
    );
    expect(activity, contains('PICKER_COPY_START'));
    expect(activity, contains('PICKER_COPY_DONE'));
    expect(activity, isNot(contains('ByteArrayOutputStream')));
    expect(activity, isNot(contains('readBytes()')));
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

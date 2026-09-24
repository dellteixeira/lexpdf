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

  test('Android file picker streams large files without file_selector buffering', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final picker = File(
      'lib/src/core/documents/document_picker_service.dart',
    ).readAsStringSync();
    final nativePicker = File(
      'lib/src/core/documents/native_android_file_picker_service.dart',
    ).readAsStringSync();

    expect(nativePicker, contains("MethodChannel('lexpdf/native_pdf_picker')"));
    expect(nativePicker, contains("'pickFile'"));
    expect(nativePicker, contains("'pickFiles'"));
    expect(picker, contains('if (Platform.isAndroid)'));
    expect(picker, contains('NativeAndroidFilePickerService'));
    final androidBranch = picker.substring(
      picker.indexOf('if (Platform.isAndroid)'),
      picker.indexOf('final file = await openFile'),
    );
    expect(androidBranch, isNot(contains('openFile(')));

    expect(activity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(activity, contains('Intent.EXTRA_ALLOW_MULTIPLE'));
    expect(activity, contains('contentResolver.openInputStream(uri)'));
    expect(activity, contains('Thread('));
    expect(activity, contains('"LexPdfPickerCopy"'));
    expect(activity, contains('"LexPdfIntentCopy"'));
    expect(
      activity,
      contains('input.copyTo(output, bufferSize = 64 * 1024)'),
    );
    expect(activity, contains('PICKER_OPEN'));
    expect(activity, contains('PICKER_COPY_START'));
    expect(activity, contains('PICKER_COPY_DONE'));
    expect(activity, isNot(contains('ByteArrayOutputStream')));
    expect(activity, isNot(contains('readBytes()')));
  });

  test('Android PDF entry points do not use file_selector or whole-file Dart bytes', () {
    final nativeProvider = File(
      'lib/src/core/cloud/native_file_provider_service.dart',
    ).readAsStringSync();
    final cloudFiles = File(
      'lib/src/screens/cloud_files_screen.dart',
    ).readAsStringSync();
    final backup = File(
      'lib/src/screens/backup_migration_screen.dart',
    ).readAsStringSync();
    final notebook = File(
      'lib/src/screens/layered_notebook_screen.dart',
    ).readAsStringSync();
    final pageTools = File(
      'lib/src/screens/pdf_page_tools_screen.dart',
    ).readAsStringSync();

    for (final source in [
      nativeProvider,
      cloudFiles,
      backup,
      notebook,
      pageTools,
    ]) {
      expect(source, contains('Platform.isAndroid'));
      expect(source, contains('NativeAndroidFilePickerService'));
    }

    expect(nativeProvider, isNot(contains('picked.readAsBytes()')));
    expect(nativeProvider, contains('File(sourcePath).copy(target.path)'));
  });

  test('diagnostics identify the exact APK generation under test', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/PdfCrashDiagnostics.kt',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(diagnostics, contains('BUILD_MARKER = "rc10-printed-index-v1"'));
    expect(diagnostics, contains(r'appendLine("build: $BUILD_MARKER")'));
    expect(pubspec, contains('version: 1.0.0-rc.10+10'));
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

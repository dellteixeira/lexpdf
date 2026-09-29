import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native PDF gate resets after reader closes so the same file can reopen', () {
    final source = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(source, contains('if (!mounted || _lastNativePath == path) return;'));
    expect(source, contains('await navigator.push('));
    expect(source, contains('if (_lastNativePath == path) _lastNativePath = null;'));
  });

  test('Android native content imports persist outside cache storage', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('File(filesDir, "native_open")'));
    expect(source, contains('uri.toString().hashCode().toUInt().toString(16)'));
    expect(source, isNot(contains('File(cacheDir, "native_open")')));
  });

  test('Android materializes native PDFs atomically before publishing path', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('File.createTempFile('));
    expect(
      source,
      contains('input.copyTo(output, bufferSize = 64 * 1024)'),
      reason: 'PDFs grandes devem ser copiados em streaming com memória limitada.',
    );
    expect(source, contains('output.flush()'));
    expect(source, contains('temporary.length() <= 0L'));
    expect(source, contains('temporary.renameTo(target)'));
    expect(source, contains('temporary.delete()'));
    expect(source, contains('querySourceVersion(uri)'));
    expect(source, contains('sourceVersion.cacheToken()'));
    expect(source, contains('PICKER_CACHE_HIT'));
    expect(
      source,
      contains('sourceVersionFile.readText() == sourceToken'),
      reason:
          'PDFs grandes inalterados devem reabrir sem repetir a cópia completa.',
    );
    expect(source, contains(r'val backup = File(targetDir, "${target.name}.bak")'));
    expect(source, contains('target.renameTo(backup)'));
    expect(source, contains('backup.renameTo(target)'));
  });

  test('Android still handles new intents while Flutter is already running', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('override fun onNewIntent(intent: Intent)'));
    expect(source, contains('setIntent(intent)'));
    expect(source, contains('channel?.invokeMethod("openPdfPath", path)'));
  });
  test('Android native reader returns and persists the last visible page', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final readerActivity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();
    final launcher = File(
      'lib/src/screens/native_pdf_reader_launcher.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsStringSync();

    expect(mainActivity, contains('OPEN_NATIVE_READER_REQUEST_CODE'));
    expect(mainActivity, contains('startActivityForResult('));
    expect(
      mainActivity,
      contains('NativePdfReaderActivity.EXTRA_LAST_PAGE'),
    );
    expect(readerActivity, contains('const val EXTRA_LAST_PAGE'));
    expect(readerActivity, contains('publishLastPageResult()'));
    expect(readerActivity, contains('putExtra(EXTRA_LAST_PAGE, currentPageIndex + 1)'));
    expect(launcher, contains("result?['lastPage']"));
    expect(launcher, contains('widget.onPageChanged(lastPage)'));
    expect(workspace, contains('_progressStore.save('));
    expect(workspace, contains('incomingProgress?.pageNumber'));
  });

}

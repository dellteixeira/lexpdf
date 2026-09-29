import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Android reader recreates chrome on rotation and preserves page', () {
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(reader, contains('override fun onConfigurationChanged'));
    expect(
      reader,
      contains('intent.putExtra(EXTRA_INITIAL_PAGE, currentPageIndex + 1)'),
    );
    expect(reader, contains('publishLastPageResult()'));
    expect(reader, contains('recreate()'));
    expect(reader, contains('48.dp'));
    expect(reader, contains('HorizontalScrollView'));
  });

  test('Android explicit imports refresh reused content URIs with recovery backup', () {
    final main = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(main, isNot(contains(
      'if (target.isFile && target.length() > 0L) return target.absolutePath',
    )));
    expect(main, contains('val backup = File(targetDir, "${target.name}.bak")'));
    expect(main, contains('target.renameTo(backup)'));
    expect(main, contains('backup.renameTo(target)'));
    expect(main, contains('input.copyTo(output, bufferSize = 64 * 1024)'));
  });

  test('TXT import does not silently replace malformed UTF-8 characters', () {
    final service = File(
      'lib/src/core/notebook/notebook_document_file_service.dart',
    ).readAsStringSync();

    expect(service, contains('utf8.decode(bytes, allowMalformed: false)'));
    expect(service, contains('const cp1252 = <int, int>'));
    expect(service, isNot(contains('allowMalformed: true')));
  });
}

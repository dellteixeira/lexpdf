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
    expect(source, contains('input.copyTo(output)'));
    expect(source, contains('output.flush()'));
    expect(source, contains('temporary.length() <= 0L'));
    expect(source, contains('temporary.renameTo(target)'));
    expect(source, contains('temporary.delete()'));
    expect(
      source,
      contains('if (target.isFile && target.length() > 0L) return target.absolutePath'),
    );
  });

  test('Android still handles new intents while Flutter is already running', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('override fun onNewIntent(intent: Intent)'));
    expect(source, contains('setIntent(intent)'));
    expect(source, contains('channel?.invokeMethod("openPdfPath", path)'));
  });
}

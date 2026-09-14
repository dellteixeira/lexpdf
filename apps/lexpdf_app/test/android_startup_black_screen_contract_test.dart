import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android startup avoids Impeller black-surface regression', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('android:name="io.flutter.embedding.android.EnableImpeller"'),
    );
    expect(manifest, contains('android:value="false"'));
  });

  test('Flutter paints a startup frame before asynchronous initialization', () {
    final source = File('lib/main.dart').readAsStringSync();

    final runAppIndex = source.indexOf('runApp(_LexPdfBootstrap');
    final pdfInitIndex = source.indexOf('await pdfrxFlutterInitialize();');
    final supabaseInitIndex = source.indexOf('await Supabase.initialize(');
    final storageInitIndex = source.indexOf('await getApplicationSupportDirectory()');

    expect(runAppIndex, greaterThanOrEqualTo(0));
    expect(pdfInitIndex, greaterThan(runAppIndex));
    expect(supabaseInitIndex, greaterThan(runAppIndex));
    expect(storageInitIndex, greaterThan(runAppIndex));
    expect(source, contains('await pdfrxFlutterInitialize();'));
    expect(source, contains("'Preparando seus documentos…'"));
    expect(source, contains("'Não foi possível iniciar o LexPDF.'"));
    expect(source, contains("label: const Text('Tentar novamente')"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses Google AndroidX PDF beta and AndroidX Ink without commercial SDK', () {
    final gradle =
        File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      gradle,
      contains('implementation("androidx.pdf:pdf-viewer-fragment:1.0.0-beta01")'),
    );
    expect(
      gradle,
      contains('implementation("androidx.pdf:pdf-ink:1.0.0-beta01")'),
    );
    expect(
      gradle,
      contains('implementation("androidx.ink:ink-authoring:1.0.0")'),
    );
    expect(gradle, isNot(contains('com.pdftron')));
    expect(gradle, isNot(contains('apryse')));
  });

  test('native AndroidX PDF activity is isolated from Flutter PDFium', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/AndroidxPdfActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".AndroidxPdfActivity"'));
    expect(manifest, contains('android:process=":androidxpdf"'));
    expect(manifest, contains('android:theme="@style/AndroidxPdfTheme"'));

    expect(activity, contains('class AndroidxPdfActivity : AppCompatActivity()'));
    expect(activity, contains('PdfViewerFragment'));
    expect(activity, contains('EditablePdfViewerFragment'));
    expect(activity, contains('SdkExtensions.getExtensionVersion'));
    expect(activity, contains('MIN_VIEWER_EXTENSION = 13'));
    expect(activity, contains('MIN_EDIT_EXTENSION = 18'));
    expect(activity, isNot(contains('PDFNet')));
    expect(activity, isNot(contains('pdfrx')));
  });

  test('AndroidX Ink path supports save, search and immediate edit mode', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/AndroidxPdfActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('isTextSearchActive = true'));
    expect(activity, contains('isEditModeEnabled = true'));
    expect(activity, contains('hasUnsavedChanges'));
    expect(activity, contains('applyDraftEdits()'));
    expect(activity, contains('handle.writeTo(descriptor)'));
    expect(activity, contains('StandardCopyOption.REPLACE_EXISTING'));
    expect(activity, contains('Anotações salvas no PDF.'));
  });

  test('Flutter Android workspace launches AndroidX engine and never mounts pdfrx reader', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final launcher =
        File('lib/src/screens/androidx_pdf_reader_launcher.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final normalizedMain = main.replaceAll(RegExp(r'\s+'), ' ');

    final nativeReader = workspace.indexOf('AndroidxPdfReaderLauncher(');
    final desktopReader = workspace.indexOf('return editor.PdfWorkspaceScreen(');

    expect(workspace, contains("import 'androidx_pdf_reader_launcher.dart';"));
    expect(nativeReader, greaterThanOrEqualTo(0));
    expect(desktopReader, greaterThan(nativeReader));
    expect(
      workspace,
      contains('Flutter never mounts the legacy pdfrx/PDFium viewer.'),
    );

    expect(launcher, contains("MethodChannel('lexpdf/androidx_pdf')"));
    expect(launcher, isNot(contains("package:pdfrx/")));
    expect(
      normalizedMain,
      contains('if (Platform.isWindows) { await pdfrxFlutterInitialize(); }'),
    );
  });

  test('AndroidX viewer has no evaluation watermark configuration', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/AndroidxPdfActivity.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(activity, contains('No commercial SDK or'));
    expect(activity, contains('evaluation watermark'));
    expect(manifest, isNot(contains('pdftron_license_key')));
    expect(manifest, isNot(contains('DocumentActivity')));
  });
}

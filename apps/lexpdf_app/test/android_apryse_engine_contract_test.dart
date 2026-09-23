import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android build integrates Apryse 12.1 native SDK from official Maven repo', () {
    final rootGradle =
        File('android/build.gradle.kts').readAsStringSync();
    final appGradle =
        File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      rootGradle,
      contains('https://pdftron-maven.s3.amazonaws.com/release'),
    );
    expect(appGradle, contains('implementation("com.pdftron:pdftron:12.1.0")'));
    expect(appGradle, contains('implementation("com.pdftron:tools:12.1.0")'));
    expect(appGradle, contains('multiDexEnabled = true'));
    expect(
      appGradle,
      contains('providers.gradleProperty("PDFTRON_LICENSE_KEY").orElse("").get()'),
    );
  });

  test('Apryse viewer runs in a dedicated Android process with large heap', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:largeHeap="true"'));
    expect(
      manifest,
      contains('android:name="com.pdftron.pdf.controls.DocumentActivity"'),
    );
    expect(manifest, contains('android:process=":apryse"'));
    expect(manifest, contains('android:theme="@style/PDFTronAppTheme"'));
    expect(manifest, contains('android:name="pdftron_license_key"'));
  });

  test('MainActivity launches Apryse DocumentActivity with Xodo-class viewer features', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('lexpdf/apryse_viewer'));
    expect(mainActivity, contains('DocumentActivity.IntentBuilder'));
    expect(mainActivity, contains('.withUri(Uri.fromFile(file))'));
    expect(mainActivity, contains('.documentEditingEnabled(true)'));
    expect(mainActivity, contains('.setStylusAsPen(true)'));
    expect(
      mainActivity,
      contains('.setAlwaysDrawWithFingerAndStylus(false)'),
    );
    expect(mainActivity, contains('.setEditInk(true)'));
    expect(mainActivity, contains('.setOpenToolbar(true)'));
    expect(mainActivity, contains('.showAnnotationToolbarOption(true)'));
    expect(mainActivity, contains('.showAnnotationsList(true)'));
    expect(mainActivity, contains('.movableToolbarEnabled(true)'));
    expect(mainActivity, contains('.fullscreenModeEnabled(false)'));
    expect(mainActivity, contains('.showSearchView(true)'));
    expect(mainActivity, contains('.showThumbnailView(true)'));
    expect(mainActivity, contains('.showOutlineList(true)'));
    expect(mainActivity, contains('.showUserBookmarksList(true)'));
    expect(mainActivity, contains('.tabletLayoutEnabled(true)'));
  });

  test('Android Flutter workspace never mounts the pdfrx reader', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final launcher = File(
      'lib/src/screens/android_apryse_pdf_reader_screen.dart',
    ).readAsStringSync();

    final androidBranch = workspace.indexOf('if (Platform.isAndroid)');
    final apryseReader = workspace.indexOf('AndroidAprysePdfReaderScreen(');
    final pdfrxReader = workspace.indexOf('return editor.PdfWorkspaceScreen(');

    expect(androidBranch, greaterThanOrEqualTo(0));
    expect(apryseReader, greaterThan(androidBranch));
    expect(pdfrxReader, greaterThan(apryseReader));
    expect(
      workspace,
      contains('No pdfrx/PDFium viewer is mounted by Flutter.'),
    );

    expect(launcher, contains("MethodChannel('lexpdf/apryse_viewer')"));
    expect(launcher, isNot(contains("package:pdfrx/")));
    expect(launcher, isNot(contains("package:pdfx/")));
  });

  test('pdfrx initialization remains Windows-only', () {
    final main = File('lib/main.dart').readAsStringSync();
    final normalized = main.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      normalized,
      contains('if (Platform.isWindows) { await pdfrxFlutterInitialize(); }'),
    );
  });
}

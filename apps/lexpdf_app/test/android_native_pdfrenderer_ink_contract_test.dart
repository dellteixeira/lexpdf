import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native reader uses platform PdfRenderer and stable AndroidX Ink', () {
    final gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('androidx.ink:ink-authoring:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-brush:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-rendering:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-storage:1.0.0'));

    expect(activity, contains('android.graphics.pdf.PdfRenderer'));
    expect(activity, contains('InProgressStrokesView'));
    expect(activity, contains('StockBrushes.pressurePen()'));
    expect(activity, contains('StockBrushes.highlighter()'));
    expect(activity, contains('ViewStrokeRenderer'));
    expect(activity, contains('MAX_RENDER_PIXELS = 8_000_000L'));

    expect(activity, isNot(contains('com.pdftron')));
    expect(activity, isNot(contains('EditablePdfViewerFragment')));
    expect(activity, isNot(contains('PdfViewerFragment')));
  });

  test('PdfRenderer activity opens only one page inside the render task', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('renderer.openPage(pageIndex).use { page ->'));
    expect(activity, contains('PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY'));
    expect(activity, contains('Executors.newSingleThreadExecutor()'));
    expect(activity, contains('rendered?.recycle()'));
    expect(activity, contains('surface.releaseBitmap()'));
  });

  test('S Pen is separated from finger pan and zoom', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('MotionEvent.TOOL_TYPE_STYLUS'));
    expect(activity, contains('MotionEvent.TOOL_TYPE_ERASER'));
    expect(activity, contains('surface.requestUnbufferedDispatch(event)'));
    expect(activity, contains('wetInkView.startStroke('));
    expect(activity, contains('wetInkView.addToStroke('));
    expect(activity, contains('wetInkView.finishStroke('));
    expect(activity, contains('ScaleGestureDetector('));
  });

  test('Ink is authored in page coordinates and stored in a sidecar', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('surface.viewToPageMatrix()'));
    expect(activity, contains('surface.pageToViewMatrix()'));
    expect(activity, contains('native_ink/'));
    expect(activity, contains('entry.stroke.inputs.encode(bytes)'));
    expect(activity, contains('StrokeInputBatch.decode('));
    expect(activity, contains('Stroke(brush, batch)'));
    expect(activity, contains('Desfazer'));
    expect(activity, contains('Refazer'));
  });

  test('Android workspace launches native reader before desktop pdfrx editor', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final launcher =
        File('lib/src/screens/native_pdf_reader_launcher.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final normalizedMain = main.replaceAll(RegExp(r'\s+'), ' ');

    final nativeReader = workspace.indexOf('NativePdfReaderLauncher(');
    final desktopReader = workspace.indexOf('return editor.PdfWorkspaceScreen(');

    expect(
      workspace,
      contains("import 'native_pdf_reader_launcher.dart';"),
    );
    expect(nativeReader, greaterThanOrEqualTo(0));
    expect(desktopReader, greaterThan(nativeReader));
    expect(
      workspace,
      contains('Flutter never mounts pdfrx/PDFium here.'),
    );
    expect(
      launcher,
      contains("MethodChannel('lexpdf/native_pdf_reader')"),
    );
    expect(
      normalizedMain,
      contains('if (Platform.isWindows) { await pdfrxFlutterInitialize(); }'),
    );
  });

  test('native activity runs in its own process and uses no commercial watermark SDK', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:name=".NativePdfReaderActivity"'));
    expect(manifest, contains('android:process=":pdfreader"'));
    expect(manifest, contains('android:theme="@style/NativePdfReaderTheme"'));
    expect(manifest, isNot(contains('pdftron_license_key')));
    expect(manifest, isNot(contains('DocumentActivity')));
  });
}

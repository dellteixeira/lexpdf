import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android reader uses streamed Mozilla PDF.js plus stable AndroidX Ink', () {
    final gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('androidx.ink:ink-authoring:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-brush:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-rendering:1.0.0'));
    expect(gradle, contains('androidx.ink:ink-storage:1.0.0'));

    expect(activity, contains('PDFJS_VERSION = "6.3.289"'));
    expect(activity, contains('shouldInterceptRequest'));
    expect(activity, contains('RangeFileInputStream'));
    expect(activity, contains('Content-Range'));
    expect(activity, contains('rangeChunkSize: 131072'));
    expect(activity, contains('disableStream: true'));
    expect(activity, contains('disableAutoFetch: true'));
    expect(activity, contains('InProgressStrokesView'));
    expect(activity, contains('StockBrushes.pressurePen()'));
    expect(activity, contains('StockBrushes.highlighter()'));

    expect(activity, isNot(contains('android.graphics.pdf.PdfRenderer')));
    expect(activity, isNot(contains('com.pdftron')));
    expect(activity, isNot(contains('EditablePdfViewerFragment')));
  });

  test('PDF.js only renders the current page and bounds the canvas pixel budget', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('const maxPixels = 8000000'));
    expect(activity, contains('pdf.getPage(target)'));
    expect(activity, contains('page.cleanup()'));
    expect(activity, contains('RenderingCancelledException'));
    expect(activity, contains('renderToken'));
  });

  test('S Pen is routed to Ink while finger interaction stays in WebView', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('MotionEvent.TOOL_TYPE_STYLUS'));
    expect(activity, contains('MotionEvent.TOOL_TYPE_ERASER'));
    expect(activity, contains('wetInkView.startStroke('));
    expect(activity, contains('wetInkView.addToStroke('));
    expect(activity, contains('wetInkView.finishStroke('));
    expect(activity, contains('class StylusRouterLayout'));
  });

  test('Ink uses PDF.js page coordinates and persists as LexPDF sidecar', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('pageToViewMatrix()'));
    expect(activity, contains('viewToPageMatrix()'));
    expect(activity, contains('pdfjs_ink/'));
    expect(activity, contains('entry.stroke.inputs.encode(bytes)'));
    expect(activity, contains('StrokeInputBatch.decode('));
    expect(activity, contains('Desfazer'));
    expect(activity, contains('Refazer'));
  });

  test('Android workspace launches isolated reader before desktop pdfrx editor', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final launcher =
        File('lib/src/screens/native_pdf_reader_launcher.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final normalizedMain = main.replaceAll(RegExp(r'\s+'), ' ');

    final nativeReader = workspace.indexOf('NativePdfReaderLauncher(');
    final desktopReader = workspace.indexOf('return editor.PdfWorkspaceScreen(');

    expect(nativeReader, greaterThanOrEqualTo(0));
    expect(desktopReader, greaterThan(nativeReader));
    expect(workspace, contains('Mozilla PDF.js'));
    expect(launcher, contains("MethodChannel('lexpdf/native_pdf_reader')"));
    expect(
      normalizedMain,
      contains('if (Platform.isWindows) { await pdfrxFlutterInitialize(); }'),
    );
  });

  test('reader process has no commercial watermark SDK', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:name=".NativePdfReaderActivity"'));
    expect(manifest, contains('android:process=":pdfreader"'));
    expect(manifest, isNot(contains('pdftron_license_key')));
    expect(manifest, isNot(contains('DocumentActivity')));
  });
}

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
    expect(activity, contains('WebView.setDataDirectorySuffix("pdfreader")'));
    expect(activity, contains('shouldInterceptRequest'));
    expect(activity, contains('PDFDataRangeTransport'));
    expect(activity, contains('NativePdfRangeTransport'));
    expect(activity, contains('LexPdfBridge.requestRange'));
    expect(activity, contains('rangeTransport.onDataRange'));
    expect(activity, contains('RANGE_CHUNK_SIZE = 512 * 1024'));
    expect(activity, contains('rangeChunkSize: RANGE_CHUNK_SIZE'));
    expect(activity, contains('JSR_NATIVE_RANGE'));
    expect(activity, contains('for (let cursor = begin; cursor < end;'));
    expect(activity, contains('rangeReader'));
    expect(activity, contains('file.seek(begin)'));
    expect(activity, contains('file.readFully(bytes)'));
    expect(activity, contains('disableStream: true'));
    expect(activity, contains('disableAutoFetch: true'));
    expect(activity, contains('InProgressStrokesView'));
    expect(activity, contains('StockBrushes.pressurePen()'));
    expect(activity, contains('StockBrushes.highlighter()'));

    expect(activity, isNot(contains('url: PDF_URL')));
    expect(activity, isNot(contains('RangeFileInputStream')));
    expect(activity, isNot(contains('Content-Range')));
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

  test('Android reader exposes direct page navigation, outline and stylus customization', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('showPageJumpDialog()'));
    expect(activity, contains('LexPDF.goToPage('));
    expect(activity, contains('pdf.getOutline()'));
    expect(activity, contains('LexPdfBridge.outline(JSON.stringify('));
    expect(activity, contains('showOutlineDialog()'));
    expect(activity, contains('Personalizar caneta'));
    expect(activity, contains('Personalizar marca-texto'));
    expect(activity, contains('SeekBar(this)'));
    expect(activity, contains('PREF_PEN_COLOR'));
    expect(activity, contains('PREF_PEN_SIZE'));
    expect(activity, contains('PREF_HIGHLIGHT_COLOR'));
    expect(activity, contains('PREF_HIGHLIGHT_SIZE'));
    expect(activity, contains('SIDECAR_VERSION = 4'));
    expect(activity, contains('output.writeInt(entry.style.colorArgb)'));
    expect(activity, contains('output.writeFloat(entry.style.size)'));
    expect(activity, contains('require(version in 2..SIDECAR_VERSION)'));
  });

  test('finger paging and ink alignment remain synchronized during scrolling', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('scheduleMetricsSync()'));
    expect(activity, contains('settleMetrics()'));
    expect(activity, contains("stage.addEventListener('scroll'"));
    expect(activity, contains("stage.addEventListener('touchmove'"));
    expect(activity, contains("stage.addEventListener('touchend'"));
    expect(activity, contains('verticalGesture'));
    expect(activity, contains('renderPage(pageNumber + 1)'));
    expect(activity, contains('renderPage(pageNumber - 1)'));
    expect(activity, contains('stage.scrollTop = 0'));
    expect(activity, contains('highlighterInkView.invalidate()'));
    expect(activity, contains('penInkView.invalidate()'));
    expect(
      activity,
      contains(
        'viewToPageMatrix(),\n                        Matrix(),',
      ),
    );
    expect(
      activity,
      isNot(
        contains(
          'viewToPageMatrix(),\n                        pageToViewMatrix(),',
        ),
      ),
    );
    expect(activity, contains('const density = window.devicePixelRatio || 1'));
    expect(activity, contains('left: r.left * density'));
    expect(activity, contains('top: r.top * density'));
    expect(activity, contains('width: r.width * density'));
    expect(activity, contains('height: r.height * density'));
  });

  test('reader builds a navigable PDF index and supports fit-page', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('pdf.getPageLabels()'));
    expect(activity, contains('pdf.getOutline()'));
    expect(activity, contains('buildVisualIndex()'));
    expect(activity, contains('buildPrintedPaginationModel'));
    expect(activity, contains("source: 'toc'"));
    expect(activity, contains("source: 'outline'"));
    expect(activity, contains('physicalPageForPrintedLabel'));
    expect(activity, contains('detectPrintedPageLabel'));
    expect(activity, contains('printedToPhysical'));
    expect(activity, contains('physicalToPrinted'));
    expect(activity, contains('inferOffsetFromTocTitles'));
    expect(activity, contains('publishDerivedPageLabels'));
    expect(activity, contains('LexPdfBridge.pageLabels'));
    expect(activity, contains('button("⛶ Página")'));
    expect(activity, contains('LexPDF.fitPage()'));
    expect(activity, contains('fitPage() {'));
    expect(activity, contains('widthScale'));
    expect(activity, contains('heightScale'));
  });

  test('toolbar labels never wrap and shrink to fit', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('setSingleLine(true)'));
    expect(activity, contains('maxLines = 1'));
    expect(activity, contains('setHorizontallyScrolling(false)'));
    expect(activity, contains('targetWidthDp'));
    expect(activity, contains('setMinWidth(targetWidthDp.dp)'));
    expect(activity, contains('ellipsize = TextUtils.TruncateAt.END'));
    expect(
      activity,
      contains('TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration'),
    );
    expect(activity, contains('TypedValue.COMPLEX_UNIT_SP'));
    expect(activity, contains('button("Fechar")'));
  });

  test('PDF index uses embedded outline destinations from PDF.js', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('const raw = await pdf.getOutline()'));
    expect(activity, contains('await pdf.getDestination(dest)'));
    expect(activity, contains('await pdf.getPageIndex(dest[0])'));
    expect(activity, contains('await resolveOutlineItem(item, 0, output)'));
    expect(activity, contains("source: 'outline'"));
    expect(
      activity,
      contains('Use the outline/bookmarks embedded in the PDF itself'),
    );
    expect(
      activity,
      isNot(contains('Prefer the table of contents printed inside the PDF')),
    );
  });

  test('underline shapes and partial eraser are available in Android reader', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('button("Sublinhar")'));
    expect(activity, contains('button("Formas")'));
    expect(activity, contains('ShapeTool.ARROW'));
    expect(activity, contains('ShapeTool.CIRCLE'));
    expect(activity, contains('ShapeTool.RECTANGLE'));
    expect(activity, contains('ShapeTool.LINE'));
    expect(activity, contains('ShapeTool.STAR'));
    expect(activity, contains('showShapeToolDialog'));
    expect(activity, contains('snapFinishedStrokes'));
    expect(activity, contains('syntheticStrokeFromPoints'));
    expect(activity, contains('EraserMode.PARTIAL'));
    expect(activity, contains('partialEraseEntry'));
    expect(activity, contains('sampledPointsForPartialErase'));
    expect(activity, contains('InkHistoryAction.Replaced'));
    expect(activity, contains('BrushRole.VECTOR'));
    expect(activity, contains('StockBrushes.marker()'));
    expect(activity, contains('InkHistoryAction.AddedBatch'));
  });

  test('stylus eraser removes pen and highlighter strokes with undo redo history', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('InkTool.ERASER'));
    expect(activity, contains('button("Borracha")'));
    expect(activity, contains('selectEraser()'));
    expect(activity, contains('MotionEvent.TOOL_TYPE_ERASER'));
    expect(activity, contains('strokeIntersectsEraser'));
    expect(activity, contains('squaredDistanceToSegment'));
    expect(activity, contains('InkHistoryAction.Removed'));
    expect(activity, contains('undoHistory'));
    expect(activity, contains('redoHistory'));
    expect(activity, contains('remove o desenho inteiro'));
    expect(activity, contains('recorta somente a região tocada'));
  });

  test('Samsung rendering avoids layer-wide blend modes that can black out WebView', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, isNot(contains('PorterDuffXfermode')));
    expect(activity, isNot(contains('PorterDuff.Mode.MULTIPLY')));
    expect(activity, contains('setLayerType(LAYER_TYPE_HARDWARE, null)'));
    expect(activity, contains('Color.argb(72, 255, 224, 64)'));
  });

  test('stylus palettes, thickness and readable highlighter compositing are enforced', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('PREF_PEN_COLOR'));
    expect(activity, contains('PREF_PEN_SIZE'));
    expect(activity, contains('PREF_HIGHLIGHT_COLOR'));
    expect(activity, contains('PREF_HIGHLIGHT_SIZE'));
    expect(activity, contains('val minSize = if (kind == InkKind.PEN) 1 else 6'));
    expect(activity, contains('val maxSize = if (kind == InkKind.PEN) 16 else 40'));
    expect(activity, contains('Color.argb(72, 255, 224, 64)'));
    expect(activity, isNot(contains('PorterDuff.Mode.MULTIPLY')));
    expect(activity, contains('updateWetInkCompositing'));
    expect(activity, contains('highlighterInkView'));
    expect(activity, contains('penInkView'));
    expect(activity, contains('values.filter { it.style.kind == kind }'));
    expect(
      activity,
      contains('O marca-texto usa transparência baixa para preservar a legibilidade do texto'),
    );
  });

  test('ink tools select in one tap and customize on long press', () {
    final activity = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('button("Caneta")'));
    expect(activity, contains('button("Marca")'));
    expect(activity, contains('setOnLongClickListener'));
    expect(activity, contains('showInkSettings(InkKind.PEN)'));
    expect(activity, contains('showInkSettings(InkKind.HIGHLIGHTER)'));
    expect(activity, contains('"✓ Caneta"'));
    expect(activity, contains('"✓ Marca"'));
    expect(activity, contains('segure para personalizar'));
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

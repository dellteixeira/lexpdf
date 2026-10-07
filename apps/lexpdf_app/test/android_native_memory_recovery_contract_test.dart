import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String nativeSource(String name) => File(
  'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/$name.kt',
).readAsStringSync();

void main() {
  test('memory pressure has callbacks and a foreground check for Android 14+', () {
    final reader = nativeSource('NativePdfReaderActivity');
    expect(reader, contains('override fun onTrimMemory(level: Int)'));
    expect(reader, contains('override fun onLowMemory()'));
    expect(reader, contains('getMemoryInfo(info)'));
    expect(reader, contains('if (info.lowMemory) trimReaderMemory(critical = true)'));
    expect(reader, contains('memoryHandler.removeCallbacks(memoryCheckRunnable)'));
    expect(reader, contains('const maxPixels = renderPixelBudget'));
    expect(reader, contains('memoryPressureActive || readerBackgrounded'));
  });

  test('process death recovery uses an atomic per-document record and existing Flutter result', () {
    final checkpoint = nativeSource('NativeReaderCheckpoint');
    final reader = nativeSource('NativePdfReaderActivity');
    final main = nativeSource('MainActivity');
    expect(checkpoint, contains('AtomicFile'));
    expect(checkpoint, contains('source.lastModified()'));
    expect(checkpoint, contains('source.length()'));
    expect(checkpoint, contains('file.finishWrite(stream)'));
    expect(checkpoint, contains('file.failWrite(stream)'));
    expect(reader, contains('NativeReaderCheckpoint.pendingPage(this, sourceFile)'));
    expect(reader, contains('NativeReaderCheckpoint.save(this, sourceFile, currentPageIndex + 1)'));
    expect(main, contains('val fallbackPage = recoveredPage ?:'));
    expect(main, contains('"lastPage" to lastPage'));
    expect(main, contains('active = false'));
  });

  test('a dead WebView returns to the launcher without reusing its renderer', () {
    final reader = nativeSource('NativePdfReaderActivity');
    final start = reader.indexOf('override fun onRenderProcessGone');
    final end = reader.indexOf('override fun shouldInterceptRequest', start);
    final callback = reader.substring(start, end);
    expect(callback, contains('rendererGone = true'));
    expect(callback, contains('publishLastPageResult()'));
    expect(callback, contains('removeView(view)'));
    expect(callback, contains('view.destroy()'));
    expect(callback, contains('finish()'));
    expect(callback, contains('return true'));
    expect(callback, isNot(contains('startActivity')));
    expect(reader, contains('if (!::webView.isInitialized || rendererGone || isDestroyed) return'));
  });

  test('memory exits are nonblocking while real crashes retain their diagnostic screen', () {
    final diagnostics = nativeSource('PdfCrashDiagnostics');
    final gate = nativeSource('CrashGateActivity');
    final main = nativeSource('MainActivity');
    expect(diagnostics, isNot(contains('rc10-printed-index-v1')));
    expect(diagnostics, contains('info.versionName'));
    expect(diagnostics, contains('info.longVersionCode'));
    expect(diagnostics, contains('if (exit.reason != ApplicationExitInfo.REASON_LOW_MEMORY) return true'));
    expect(diagnostics, contains('now - exit.timestamp in 0..MAIN_EXIT_FRESHNESS_MS'));
    expect(gate, contains('PdfCrashDiagnostics.isMemoryPressureReport(report)'));
    expect(main, contains('PdfCrashDiagnostics.isMemoryPressureReport(report)'));
    expect(gate, contains('showDiagnostic(report)'));
    expect(main, contains('.setTitle("Diagnóstico de falha do LexPDF")'));
  });
}

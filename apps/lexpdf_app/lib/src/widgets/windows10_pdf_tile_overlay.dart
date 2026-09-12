import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'windows_native_pdf_surface.dart';

/// Returns the Windows build number from [Platform.operatingSystemVersion].
int? parseWindowsBuildNumber(String version) {
  final dotted = RegExp(r'10\.0\.(\d{5})').allMatches(version).toList();
  if (dotted.isNotEmpty) {
    return int.tryParse(dotted.last.group(1)!);
  }
  final named = RegExp(
    r'build\s*[:=]?\s*(\d{5})',
    caseSensitive: false,
  ).allMatches(version).toList();
  if (named.isNotEmpty) {
    return int.tryParse(named.last.group(1)!);
  }
  return null;
}

/// Historical name retained to avoid broad workspace churn.
///
/// Phase 7E intentionally abandons the previous PDFium/Flutter rendering
/// experiments. Every native Windows build now uses Windows.Data.Pdf painted
/// into a native child HWND. An explicit environment opt-out remains available
/// for diagnostics only.
bool isWindows10ManualTileRenderingEnabled() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;

  final optOut = Platform.environment['LEXPDF_WINDOWS_NATIVE_PDF'];
  if (optOut == '0') return false;
  return true;
}

/// Compatibility wrapper for the existing workspace overlay hook.
///
/// Despite the historical class name, this no longer renders Dart tiles,
/// ui.Image objects, Flutter textures, RawImage, pdfrx page bitmaps, or PDFium
/// pixels. The visible page is owned by Windows.Data.Pdf and a native child
/// HWND created by the Win32 runner.
class Windows10PdfTileOverlay extends StatelessWidget {
  const Windows10PdfTileOverlay({
    required this.page,
    required this.pageRect,
    required this.controller,
    super.key,
  });

  final PdfPage page;
  final Rect pageRect;
  final PdfViewerController controller;

  @override
  Widget build(BuildContext context) {
    final path = page.document.sourceName;
    if (path.isEmpty || path.startsWith('memory:') || path.startsWith('asset:')) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text(
            'WINPDF NATIVE requer um arquivo PDF local.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return WindowsNativePdfSurface(
      documentPath: path,
      page: page,
      pageRect: pageRect,
      controller: controller,
    );
  }
}

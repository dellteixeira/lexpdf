import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/widgets/windows10_pdf_tile_overlay.dart';

void main() {
  test('Windows build parser remains available for diagnostics', () {
    expect(
      parseWindowsBuildNumber(
        'Microsoft Windows [Version 10.0.19045.4780]',
      ),
      19045,
    );
    expect(
      parseWindowsBuildNumber('Windows 11 Pro 10.0.22631'),
      22631,
    );
    expect(parseWindowsBuildNumber('OS Build 19045'), 19045);
    expect(parseWindowsBuildNumber('unknown version'), isNull);
  });

  test('Phase 7E abandons Flutter PDF pixels on native Windows', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final compatibilityOverlay = File(
      'lib/src/widgets/windows10_pdf_tile_overlay.dart',
    ).readAsStringSync();
    final nativeWidget = File(
      'lib/src/widgets/windows_native_pdf_surface.dart',
    ).readAsStringSync();
    final nativeRunner = File(
      'windows/runner/windows_native_pdf_surface.cpp',
    ).readAsStringSync();
    final flutterWindow = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(workspace, contains('isWindows10ManualTileRenderingEnabled()'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));

    expect(compatibilityOverlay, contains('LEXPDF_WINDOWS_NATIVE_PDF'));
    expect(compatibilityOverlay, contains('WindowsNativePdfSurface('));
    expect(compatibilityOverlay, isNot(contains('widget.page.render(')));
    expect(compatibilityOverlay, isNot(contains('RawImage(')));
    expect(compatibilityOverlay, isNot(contains('Texture(')));
    expect(compatibilityOverlay, isNot(contains('decodeImageFromPixels')));

    expect(nativeWidget, contains("MethodChannel('lexpdf/windows_native_pdf')"));
    expect(nativeWidget, contains("'showPage'"));
    expect(nativeWidget, contains("'disposeSurface'"));
    expect(nativeWidget, contains('localToGlobal(Offset.zero)'));
    expect(nativeWidget, contains('devicePixelRatio'));

    expect(nativeRunner, contains('Windows::Data::Pdf::PdfDocument'));
    expect(nativeRunner, contains('RenderToStreamAsync'));
    expect(nativeRunner, contains('GUID_WICPixelFormat32bppBGRA'));
    expect(nativeRunner, contains('SetDIBitsToDevice'));
    expect(nativeRunner, isNot(contains('StretchDIBits')));
    expect(nativeRunner, contains('MapWindowPoints'));
    expect(nativeRunner, contains('WINPDF NATIVE'));
    expect(nativeRunner, isNot(contains('FPDF_RenderPageBitmap')));
    expect(nativeRunner, isNot(contains('FlutterDesktopPixelBuffer')));

    expect(
      flutterWindow,
      contains('RegisterWindowsNativePdfSurfaceChannel'),
    );
    expect(flutterWindow, contains('GetHandle()'));
    expect(cmake, contains('windows_native_pdf_surface.cpp'));
    expect(cmake, contains('windowsapp.lib'));
    expect(cmake, contains('windowscodecs.lib'));
  });
}

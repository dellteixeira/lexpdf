import 'dart:io';

import 'package:flutter/services.dart';

class NativePdfOpenService {
  NativePdfOpenService();

  static const MethodChannel _channel = MethodChannel('lexpdf/native_pdf_open');

  Future<void> start(Future<void> Function(String path) onOpen) async {
    if (Platform.isAndroid || Platform.isMacOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'openPdfPath') return;
        final path = call.arguments as String?;
        if (path == null || !_looksLikePdf(path)) return;
        await onOpen(path);
      });

      try {
        final initialPath = await _channel.invokeMethod<String>('getInitialPdfPath');
        if (initialPath != null && _looksLikePdf(initialPath)) {
          await onOpen(initialPath);
        }
      } on MissingPluginException {
        // Native intake is optional on unsupported/test hosts.
      } on PlatformException {
        // Keep the normal file picker available if native intake fails.
      }
    }
  }

  void dispose() {
    if (Platform.isAndroid || Platform.isMacOS) {
      _channel.setMethodCallHandler(null);
    }
  }

  static String? pdfPathFromArgs(List<String> args) {
    for (final value in args) {
      if (_looksLikePdf(value)) return value;
    }
    return null;
  }

  static bool _looksLikePdf(String value) =>
      value.trim().toLowerCase().endsWith('.pdf');
}

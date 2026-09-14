import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class WindowsPdfCompatResult {
  const WindowsPdfCompatResult({
    required this.path,
    required this.normalized,
    required this.reason,
  });

  final String path;
  final bool normalized;
  final String reason;
}

class WindowsPdfCompatNormalizer {
  const WindowsPdfCompatNormalizer();

  static const MethodChannel _channel =
      MethodChannel('lexpdf/windows_pdf_compat');

  static const int _probeWindowBytes = 8 * 1024 * 1024;
  static const int _minimumUsefulPdfBytes = 1024;

  Future<WindowsPdfCompatResult> prepare(String sourcePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'not-windows',
      );
    }

    if (Platform.environment['LEXPDF_DISABLE_PDF_COMPAT_NORMALIZATION'] == '1') {
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'disabled-by-environment',
      );
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'source-missing',
      );
    }

    final stat = await source.stat();
    if (stat.size < _minimumUsefulPdfBytes) {
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'source-too-small',
      );
    }

    final forced =
        Platform.environment['LEXPDF_FORCE_PDF_COMPAT_NORMALIZATION'] == '1';
    final probe = await _readProbe(source, stat.size);
    final tagged = probe.contains('/StructTreeRoot') || probe.contains('/MarkInfo');
    final officeGenerated = probe.contains('LibreOffice') ||
        probe.contains('OpenOffice') ||
        probe.contains('Writer');

    // The physical Windows failure was isolated to a LibreOffice-generated,
    // tagged PDF. Do not rewrite arbitrary documents: normalize only the
    // proven-risk family unless explicitly forced for diagnostics.
    if (!forced && !(tagged && officeGenerated)) {
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'no-risk-signature',
      );
    }

    final cacheRoot = await getApplicationCacheDirectory();
    final cacheDir = Directory(
      '${cacheRoot.path}${Platform.pathSeparator}pdf_compat_normalized',
    );
    await cacheDir.create(recursive: true);

    final keyMaterial = '$sourcePath|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|pdfium-import-v1';
    final key = sha256.convert(utf8.encode(keyMaterial)).toString();
    final destination = File(
      '${cacheDir.path}${Platform.pathSeparator}compat_$key.pdf',
    );

    if (await _isUsableCachedCopy(destination)) {
      return WindowsPdfCompatResult(
        path: destination.path,
        normalized: true,
        reason: 'cache-hit',
      );
    }

    final temporary = File('${destination.path}.part-${pid.toString()}');
    try {
      if (await temporary.exists()) await temporary.delete();

      final response = await _channel.invokeMapMethod<String, dynamic>(
        'normalize',
        <String, dynamic>{
          'sourcePath': source.path,
          'destinationPath': temporary.path,
        },
      );

      if (response == null || response['ok'] != true) {
        throw StateError('Native PDF compatibility normalization failed');
      }
      if (!await _isUsableCachedCopy(temporary)) {
        throw StateError('Normalized PDF was not created correctly');
      }

      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);

      return WindowsPdfCompatResult(
        path: destination.path,
        normalized: true,
        reason: 'normalized',
      );
    } on MissingPluginException {
      if (await temporary.exists()) await temporary.delete();
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'native-normalizer-unavailable',
      );
    } on PlatformException catch (error) {
      if (await temporary.exists()) await temporary.delete();
      debugPrint(
        '[LexPDF][PdfCompat] normalization failed: '
        '${error.code}: ${error.message}',
      );
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'native-normalizer-failed',
      );
    } catch (error) {
      if (await temporary.exists()) await temporary.delete();
      debugPrint('[LexPDF][PdfCompat] normalization failed: $error');
      return WindowsPdfCompatResult(
        path: sourcePath,
        normalized: false,
        reason: 'normalization-exception',
      );
    }
  }

  Future<bool> _isUsableCachedCopy(File file) async {
    if (!await file.exists()) return false;
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file &&
        stat.size >= _minimumUsefulPdfBytes;
  }

  Future<String> _readProbe(File file, int size) async {
    final handle = await file.open();
    try {
      if (size <= _probeWindowBytes * 2) {
        final bytes = await handle.read(size);
        return latin1.decode(bytes);
      }

      final head = await handle.read(_probeWindowBytes);
      await handle.setPosition(size - _probeWindowBytes);
      final tail = await handle.read(_probeWindowBytes);
      final combined = Uint8List(head.length + tail.length)
        ..setRange(0, head.length, head)
        ..setRange(head.length, head.length + tail.length, tail);
      return latin1.decode(combined);
    } finally {
      await handle.close();
    }
  }
}

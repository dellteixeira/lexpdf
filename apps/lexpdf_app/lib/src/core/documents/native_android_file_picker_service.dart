import 'dart:io';

import 'package:flutter/services.dart';

class NativeAndroidPickedFile {
  const NativeAndroidPickedFile({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class NativeAndroidFilePickerService {
  const NativeAndroidFilePickerService();

  static const MethodChannel _channel =
      MethodChannel('lexpdf/native_pdf_picker');

  Future<NativeAndroidPickedFile?> pickFile({
    required List<String> extensions,
    String mimeType = '*/*',
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'NativeAndroidFilePickerService is Android-only.',
      );
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickFile',
      <String, dynamic>{
        'mimeType': mimeType,
        'extensions': extensions,
      },
    );
    if (result == null) return null;

    final path = result['path'] as String?;
    final name = result['name'] as String?;
    if (path == null || path.trim().isEmpty) {
      throw PlatformException(
        code: 'picker_missing_path',
        message: 'Android picker returned no local file path.',
      );
    }

    return NativeAndroidPickedFile(
      path: path,
      name: (name == null || name.trim().isEmpty)
          ? File(path).uri.pathSegments.last
          : name,
    );
  }

  Future<List<NativeAndroidPickedFile>> pickFiles({
    required List<String> extensions,
    String mimeType = '*/*',
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'NativeAndroidFilePickerService is Android-only.',
      );
    }

    final raw = await _channel.invokeListMethod<dynamic>(
      'pickFiles',
      <String, dynamic>{
        'mimeType': mimeType,
        'extensions': extensions,
      },
    );
    if (raw == null) return const <NativeAndroidPickedFile>[];

    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) {
          final path = item['path'] as String?;
          final name = item['name'] as String?;
          if (path == null || path.trim().isEmpty) return null;
          return NativeAndroidPickedFile(
            path: path,
            name: (name == null || name.trim().isEmpty)
                ? File(path).uri.pathSegments.last
                : name,
          );
        })
        .whereType<NativeAndroidPickedFile>()
        .toList(growable: false);
  }
}

import 'dart:typed_data';

import 'package:flutter/services.dart';

class LegacyWordConverter {
  const LegacyWordConverter();

  static const MethodChannel _channel = MethodChannel(
    'lexpdf/legacy_word_converter',
  );

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Uint8List?> toDocx(
    Uint8List sourceBytes, {
    required String sourceExtension,
  }) async {
    if (!await isAvailable()) return null;
    final result = await _channel.invokeMethod<Uint8List>('toDocx', {
      'bytes': sourceBytes,
      'sourceExtension': sourceExtension.toLowerCase(),
    });
    return result;
  }

  Future<Uint8List?> fromDocx(
    Uint8List docxBytes, {
    required String targetExtension,
  }) async {
    if (!await isAvailable()) return null;
    final result = await _channel.invokeMethod<Uint8List>('fromDocx', {
      'bytes': docxBytes,
      'targetExtension': targetExtension.toLowerCase(),
    });
    return result;
  }
}

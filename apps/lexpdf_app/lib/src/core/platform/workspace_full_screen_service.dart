import 'dart:io';

import 'package:flutter/services.dart';

class WorkspaceFullScreenService {
  const WorkspaceFullScreenService();

  static const MethodChannel _windowsChannel =
      MethodChannel('lexpdf/window_mode');

  Future<void> setEnabled(bool enabled) async {
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      return;
    }
    if (Platform.isWindows) {
      await _windowsChannel.invokeMethod<bool>('setFullScreen', enabled);
    }
  }
}

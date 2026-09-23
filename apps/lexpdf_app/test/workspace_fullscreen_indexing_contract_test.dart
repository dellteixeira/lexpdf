import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace fullscreen is exposed in menu, shortcut and native Windows channel', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final service =
        File('lib/src/core/platform/workspace_full_screen_service.dart')
            .readAsStringSync();
    final native =
        File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(workspace, contains("'fullscreen'"));
    expect(workspace, contains("'Tela cheia'"));
    expect(workspace, contains('LogicalKeyboardKey.f11'));
    expect(
      workspace,
      contains('bind(LogicalKeyboardKey.keyH, _toggleFullScreen)'),
    );
    expect(workspace, contains('onToggleFullScreen: _toggleFullScreen'));
    expect(workspace, contains('showDocumentHeader: false'));
    expect(service, contains("MethodChannel('lexpdf/window_mode')"));
    expect(service, contains('SystemUiMode.immersiveSticky'));
    expect(native, contains('"lexpdf/window_mode"'));
    expect(native, contains('SetFullScreen'));
    expect(native, contains('MonitorFromWindow'));
    expect(native, contains('SetWindowLongPtrW'));
  });

  test('background OCR stays invisible while preserving progress', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    expect(workspace, contains('task.progress = progress'));
    expect(workspace, isNot(contains('_OcrProgressCard')));
    expect(workspace, isNot(contains('OCR preparando…')));
    expect(workspace, isNot(contains('OCR/indexação em segundo plano')));
    expect(workspace, isNot(contains('Índice atualizado')));
  });
}

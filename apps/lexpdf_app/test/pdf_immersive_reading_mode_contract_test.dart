import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF workspace exposes immersive reading mode on Android and Windows', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final androidRouter = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();

    expect(workspace, contains('bool _readingMode = false;'));
    expect(
      workspace,
      contains("appBar: (_readingMode || !widget.showDocumentHeader)"),
    );
    expect(workspace, contains('if (!_readingMode) _buildCommandBar(path)'));
    expect(workspace, contains('onSingleTap: _handleAndroidPdfTap'));
    expect(workspace, contains('_requestFullScreen();'));
    expect(workspace, contains('showDocumentHeader'));
    expect(workspace, contains('SystemUiMode.immersiveSticky'));
    expect(workspace, contains('SystemUiMode.edgeToEdge'));
    expect(
      workspace,
      contains(
        'const SingleActivator(LogicalKeyboardKey.keyH, control: true)',
      ),
    );
    expect(workspace, contains('LogicalKeyboardKey.escape'));
    expect(workspace, contains('_WorkspaceMoreAction.readingMode'));
    expect(
      workspace,
      contains("title: Text('Modo leitura em tela cheia')"),
    );
    expect(workspace, contains('Icons.fullscreen_outlined'));

    expect(androidRouter, contains('final VoidCallback? onSingleTap;'));
    expect(androidRouter, contains('_tapMoveTolerance'));
    expect(androidRouter, contains('_tapDisqualified'));
    expect(
      androidRouter,
      contains('!PdfAndroidTouchInputPolicy.compactPhoneInkActive'),
    );
    expect(androidRouter, contains('widget.onSingleTap?.call();'));
  });
}

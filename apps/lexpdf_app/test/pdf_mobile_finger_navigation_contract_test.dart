import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF toolbar has a single zoom control group', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();

    final appBarStart = source.indexOf('appBar: AppBar(');
    final bodyStart = source.indexOf('body: CallbackShortcuts', appBarStart);
    expect(appBarStart, greaterThanOrEqualTo(0));
    expect(bodyStart, greaterThan(appBarStart));

    final appBar = source.substring(appBarStart, bodyStart);
    expect(appBar, isNot(contains('Icons.zoom_out')));
    expect(appBar, isNot(contains('Icons.zoom_in')));
    expect(appBar, isNot(contains('_buildZoomMenu')));
    expect(appBar, contains("Text('Pág. \$_page')"));

    final commandBarStart = source.indexOf('Widget _buildCommandBar');
    final stylusButtonStart = source.indexOf('Widget _stylusButton', commandBarStart);
    final commandBar = source.substring(commandBarStart, stylusButtonStart);
    expect(commandBar, contains('Icons.zoom_out'));
    expect(commandBar, contains('_buildZoomMenu()'));
    expect(commandBar, contains('Icons.zoom_in'));
  });

  test('mobile PDF navigation remains enabled in every active tool', () {
    final workspace = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();
    final overlay = File('lib/src/widgets/pdf_stylus_page_overlay.dart')
        .readAsStringSync();

    expect(
      workspace,
      contains(
        'panEnabled:\n                              _mobile ||\n                              (_stylusMode != _StylusMode.note && !_inkMode)',
      ),
    );
    expect(
      workspace,
      contains(
        'scaleEnabled:\n                              _mobile ||\n                              (_stylusMode != _StylusMode.note && !_inkMode)',
      ),
    );

    // Finger input must be left to the PdfViewer instead of being converted
    // into ink on compact Android phones.
    expect(overlay, isNot(contains('_compactTouchDrawing')));
    expect(overlay, isNot(contains('onPanStart:')));
    expect(overlay, isNot(contains('onPanUpdate:')));
    expect(overlay, isNot(contains('onPanEnd:')));
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, contains('behavior: HitTestBehavior.translucent'));
  });
}

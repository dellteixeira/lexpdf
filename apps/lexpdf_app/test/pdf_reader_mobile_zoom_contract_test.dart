import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile reader keeps pan and pinch zoom enabled while ink mode is active', () {
    final source = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();
    expect(source, contains('defaultTargetPlatform == TargetPlatform.android'));
    expect(source, contains('defaultTargetPlatform == TargetPlatform.iOS'));
    expect(
      source,
      contains('panEnabled: !_inkMode || _mobileTouchNavigationEnabled'),
    );
    expect(
      source,
      contains('scaleEnabled: !_inkMode || _mobileTouchNavigationEnabled'),
    );
    expect(source, isNot(contains('scaleEnabled: !_inkMode,')));
  });

  test('ink overlay reserves touch input for viewer navigation', () {
    final source = File('lib/src/widgets/pdf_ink_page_overlay.dart').readAsStringSync();
    expect(source, contains('PointerDeviceKind.stylus'));
    expect(source, contains('PointerDeviceKind.invertedStylus'));
    expect(source, contains('PointerDeviceKind.mouse'));
    expect(source, isNot(contains('event.kind == PointerDeviceKind.touch')));
  });

  test('reader chrome is extracted from the screen state', () {
    final screen = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();
    final controls = File('lib/src/widgets/pdf_reader_controls.dart').readAsStringSync();
    expect(screen, contains("import '../widgets/pdf_reader_controls.dart';"));
    expect(screen, contains('PdfReaderAppBarActions('));
    expect(screen, contains('PdfSearchAppBarActions('));
    expect(screen, contains('PdfInkStatusCard('));
    expect(controls, contains('class PdfReaderAppBarActions'));
    expect(controls, contains('class PdfSearchAppBarActions'));
    expect(controls, contains('class PdfInkStatusCard'));
  });
}

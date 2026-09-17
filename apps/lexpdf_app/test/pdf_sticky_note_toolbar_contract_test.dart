import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace exposes compact rich sticky-note pins and removes pencil tool', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final overlay =
        File('lib/src/widgets/pdf_sticky_note_overlay.dart').readAsStringSync();

    expect(workspace, contains('_StylusMode.note'));
    expect(workspace, contains("'Anotar'"));
    expect(workspace, contains('PdfStickyNoteOverlay('));
    expect(workspace, isNot(contains("'Lápis'")));
    expect(workspace, isNot(contains('_StylusMode.pencil')));

    expect(overlay, contains('Icons.push_pin_rounded'));
    expect(overlay, contains('static const _markerSize = 26.0'));
    expect(overlay, contains("tooltip: 'Negrito'"));
    expect(overlay, contains("tooltip: 'Itálico'"));
    expect(overlay, contains("tooltip: 'Sublinhado'"));
    expect(overlay, contains('DropdownButton<double>('));
    expect(overlay, contains('DropdownButton<String>('));
    expect(overlay, contains("'fontFamily': fontFamily"));
    expect(overlay, contains("'textAlign': textAlign"));
    expect(overlay, contains('Icons.format_align_justify'));
    expect(overlay, contains("prefix = 'lexpdf-note-v1:'"));
    expect(overlay, contains("label: const Text('Salvar')"));
  });
}

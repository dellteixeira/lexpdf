import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace exposes Acrobat-style sticky notes and removes pencil tool', () {
    final workspace =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final overlay =
        File('lib/src/widgets/pdf_sticky_note_overlay.dart').readAsStringSync();

    expect(workspace, contains('_StylusMode.note'));
    expect(workspace, contains("'Anotar'"));
    expect(workspace, contains('PdfStickyNoteOverlay('));
    expect(workspace, isNot(contains("'Lápis'")));
    expect(workspace, isNot(contains('_StylusMode.pencil')));

    expect(overlay, contains('Icons.sticky_note_2'));
    expect(overlay, contains("tooltip: 'Negrito'"));
    expect(overlay, contains("tooltip: 'Itálico'"));
    expect(overlay, contains("tooltip: 'Sublinhado'"));
    expect(overlay, contains("message: 'Tamanho da fonte'"));
    expect(overlay, contains("prefix = 'lexpdf-note-v1:'"));
    expect(overlay, contains("label: const Text('Salvar')"));
  });
}

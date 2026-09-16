import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF workspace is a persistent multi-tab shell around the editor', () {
    final source = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();

    expect(source, contains('IndexedStack('));
    expect(source, contains('LocalPdfWorkspaceSessionStore'));
    expect(source, contains('DocumentPickerService'));
    expect(source, contains("'Nova aba de PDF (Ctrl+T)'"));
    expect(source, contains('editor.PdfWorkspaceScreen('));
    expect(source, contains('didChangeAppLifecycleState'));
    expect(source, contains('await _sessionStore.save('));
  });

  test('PDF workspace exposes persistent undo and redo shortcuts', () {
    final source = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();
    final inkStore = File('lib/src/core/storage/local_pdf_ink_store.dart')
        .readAsStringSync();

    expect(source, contains('LogicalKeyboardKey.keyZ'));
    expect(source, contains('LogicalKeyboardKey.keyY'));
    expect(source, contains("'Desfazer (Ctrl+Z)'"));
    expect(source, contains("'Refazer (Ctrl+Y)'"));
    expect(source, contains('await _inkStore.undo('));
    expect(source, contains('await _inkStore.redo('));
    expect(inkStore, contains('CREATE TABLE IF NOT EXISTS pdf_ink_history'));
    expect(inkStore, contains('DELETE FROM pdf_ink_history WHERE document_id = ? AND undone = 1'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library documents open directly in the unified PDF workspace', () {
    final library = File('lib/src/screens/library_screen.dart')
        .readAsStringSync();
    final documentRef = File('lib/src/core/documents/document_provider.dart')
        .readAsStringSync();

    expect(library, contains('Documentos da biblioteca'));
    expect(library, contains("'Clique para abrir em Trabalhar com PDF'"));
    expect(library, contains('final canOpen = _hasLocalPath(document);'));
    expect(
      library,
      contains(
        'onTap: canOpen ? () => _openWorkspaceDocument(document) : null',
      ),
    );
    expect(library, contains('builder: (_) => PdfWorkspaceScreen('));
    expect(
      documentRef,
      contains('provider == DocumentProviderKind.local ? id : null'),
    );
  });

  test('Cadernos abre diretamente a nova galeria stylus-first', () {
    final home = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();
    final hub = File('lib/src/screens/notebook_screen.dart').readAsStringSync();
    final editor = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();

    expect(home, contains('section == _HomeSection.notebooks'));
    expect(home, contains('_openNotebook'));
    expect(home, isNot(contains("action: 'Abrir cadernos'")));
    expect(hub, contains('StylusNotebookEditorScreen'));
    expect(editor, contains('TransformationController'));
    expect(editor, contains('InkCanvas'));
    expect(editor, contains('panEnabled: _hand'));
    expect(editor, contains('scaleEnabled: true'));
  });
}

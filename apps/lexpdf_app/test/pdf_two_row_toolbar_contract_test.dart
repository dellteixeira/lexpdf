import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF command bar uses two responsive rows without horizontal scrolling', () {
    final source =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget _buildCommandBar');
    final end = source.indexOf('Widget _stylusButton', start);
    final commandBar = source.substring(start, end);

    expect(commandBar, contains('rowHeight * 2'));
    expect(commandBar, contains('_fitToolbarRow'));
    expect(commandBar, contains('constraints.maxWidth < 760'));
    expect(commandBar, isNot(contains('SingleChildScrollView')));
    expect(commandBar, contains("'Tela cheia (F11)'"));
    expect(commandBar, contains("'Mais ferramentas'"));
  });

  test('compact Android toolbar keeps secondary tools reachable', () {
    final source =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    expect(source, contains('_WorkspaceMoreAction.outline'));
    expect(source, contains('_WorkspaceMoreAction.bookmarks'));
    expect(source, contains("title: Text('Sumário')"));
    expect(source, contains("title: Text('Marcadores')"));
    expect(source, contains('widget.fullScreen'));
  });
}

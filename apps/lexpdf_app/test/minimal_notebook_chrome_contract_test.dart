import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook navigation becomes contextual on compact layouts', () {
    final source = File(
      'lib/src/widgets/notebook_editor_chrome.dart',
    ).readAsStringSync();

    expect(source, contains('width < 760'));
    expect(source, contains('PopupMenuButton<_NotebookPageAction>'));
    expect(source, contains("tooltip: 'Ações da página'"));
    expect(source, contains("tooltip: 'Template da página'"));
    expect(source, contains("'Adicionar página'"));
    expect(source, contains("'Duplicar página'"));
    expect(source, contains("'Excluir página'"));
  });

  test('notebook navigation keeps primary page motion directly accessible', () {
    final source = File(
      'lib/src/widgets/notebook_editor_chrome.dart',
    ).readAsStringSync();

    expect(source, contains("tooltip: 'Página anterior'"));
    expect(source, contains("tooltip: 'Próxima página'"));
    expect(source, contains("'\${page?.pageNumber ?? 0}/\$pageCount'"));
  });

  test('notebook layer and zoom chrome are lightweight', () {
    final source = File(
      'lib/src/widgets/notebook_editor_chrome.dart',
    ).readAsStringSync();

    expect(source, contains('elevation: 0'));
    expect(source, contains('Icons.visibility_off_outlined'));
    expect(source, contains('Icons.lock_outline'));
    expect(source, isNot(contains("Chip(label: Text('Oculta'))")));
    expect(source, isNot(contains("Chip(label: Text('Bloqueada'))")));
  });

  test('notebook editor toolbar stays flat and compact', () {
    final source = File(
      'lib/src/widgets/notebook_editor_toolbar.dart',
    ).readAsStringSync();

    expect(source, contains('height: 54'));
    expect(source, contains('SingleChildScrollView('));
    expect(source, isNot(contains('thumbVisibility: true')));
    expect(source, isNot(contains('trackVisibility: true')));
    expect(source, isNot(contains('border: Border.all')));
    expect(source, contains('surfaceContainerLow.withValues(alpha: 0.72)'));
  });
}

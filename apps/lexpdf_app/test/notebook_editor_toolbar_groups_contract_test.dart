import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook toolbar composes extracted lasso and style groups', () {
    final toolbar = File('lib/src/widgets/notebook_editor_toolbar.dart')
        .readAsStringSync();
    final groups = File('lib/src/widgets/notebook_editor_toolbar_groups.dart')
        .readAsStringSync();

    expect(toolbar, contains("import 'notebook_editor_toolbar_groups.dart';"));
    expect(toolbar, contains('NotebookLassoTools('));
    expect(toolbar, contains('NotebookStyleControls('));
    expect(groups, contains('class NotebookLassoTools extends StatelessWidget'));
    expect(groups, contains('class NotebookStyleControls extends StatelessWidget'));
    expect(groups, contains("tooltip: 'Reconhecer forma'"));
    expect(groups, contains("tooltip: 'Limpar camada ativa'"));
  });
}

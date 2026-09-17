import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phase 7 keeps productivity chrome outside the PDF editor', () {
    final shell = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();

    expect(
      shell,
      contains("import 'pdf_workspace_stylus_screen.dart' as editor;"),
    );
    expect(shell, contains('editor.PdfWorkspaceScreen('));
    expect(shell, contains('IndexedStack('));
    expect(shell, contains('CallbackShortcuts('));
  });

  test('workspace exposes adaptive panel, status and command palette', () {
    final shell = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();

    expect(shell, contains('_sidePanelBreakpoint'));
    expect(shell, contains('_desktopMenuBreakpoint'));
    expect(shell, contains('Paleta de comandos'));
    expect(shell, contains('Workspace'));
    expect(shell, contains('_buildStatusBar'));
    expect(shell, contains('Ctrl+Shift+P'));
    expect(shell, contains('Ctrl+Shift+I'));
    expect(shell, contains('Ctrl+B'));
  });

  test('workspace presentation preferences are persisted locally', () {
    final prefs = File(
      'lib/src/core/storage/local_workspace_ui_preferences.dart',
    ).readAsStringSync();
    final shell = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();

    expect(prefs, contains('workspace_ui_preferences'));
    expect(prefs, contains('panelVisibleKey'));
    expect(prefs, contains('statusBarVisibleKey'));
    expect(prefs, contains('denseToolbarKey'));
    expect(shell, contains('LocalWorkspaceUiPreferences'));
    expect(shell, contains('_toggleWorkspacePanel'));
    expect(shell, contains('_toggleStatusBar'));
    expect(shell, contains('_toggleDenseToolbar'));
  });

  test('desktop menus cover file edit view tools study and help', () {
    final shell = File('lib/src/screens/pdf_workspace_screen.dart')
        .readAsStringSync();

    for (final menu in [
      "label: 'Arquivo'",
      "label: 'Editar'",
      "label: 'Exibir'",
      "label: 'Ferramentas'",
      "label: 'Estudo'",
      "label: 'Ajuda'",
    ]) {
      expect(shell, contains(menu));
    }
  });
}

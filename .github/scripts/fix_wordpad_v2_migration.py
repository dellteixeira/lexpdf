from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/lexpdf_app"
DATABASE = APP / "lib/src/core/storage/local_database.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


def patch_file(relative_path: str, replacements: list[tuple[str, str, str]]) -> None:
    path = APP / relative_path
    text = path.read_text(encoding="utf-8")
    for old, new, label in replacements:
        text = replace_once(text, old, new, f"{relative_path}: {label}")
    path.write_text(text, encoding="utf-8")


# The first patch intentionally injects the v10 block just before close().
# Move that block back inside _migrate() before formatting/analyzing.
text = DATABASE.read_text(encoding="utf-8")
pattern = re.compile(
    r"\n  \}\n\n\n(    if \(version < 10\) \{.*?\n    \})\n\n  void close\(\) => database\.dispose\(\);",
    re.S,
)
replacement = r"\n\n\1\n  }\n\n  void close() => database.dispose();"
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(
        f"schema v10 migration relocation: expected exactly one match, got {count}"
    )
DATABASE.write_text(text, encoding="utf-8")
print("Schema v10 migration moved inside _migrate().")

# Schema v10 is now the real current schema. Keep the layer regression test,
# but make its version assertion describe the database that the app actually opens.
patch_file(
    "test/local_notebook_layer_store_test.dart",
    [
        (
            "test('schema 9 creates and persists ordered notebook layers', () async {",
            "test('schema 10 creates and persists ordered notebook layers', () async {",
            "schema test name",
        ),
        (
            "expect(database.database.userVersion, 9);",
            "expect(database.database.userVersion, 10);",
            "schema version assertion",
        ),
    ],
)

# The WordPad redesign deliberately replaces the old zoom overlay and mobile-like
# buttons. Preserve the behavioural checks while pointing source contracts at the
# new ribbon/status-bar implementation.
patch_file(
    "test/desktop_pdf_notebook_navigation_contract_test.dart",
    [
        (
            "'lib/src/widgets/notebook_editor_chrome.dart',",
            "'lib/src/widgets/notebook_wordpad_chrome.dart',",
            "WordPad chrome source",
        ),
        (
            "expect(controls, contains(\"label: const Text('Selecionar')\"));",
            "expect(controls, contains(\"label: 'Selecionar'\"));",
            "selection command contract",
        ),
        (
            "expect(controls, contains(\"label: const Text('Mão')\"));",
            "expect(controls, contains(\"label: 'Mão'\"));",
            "hand command contract",
        ),
        (
            "expect(zoom, contains('NotebookZoomControls'));",
            "expect(zoom, contains('class NotebookWordPadStatusBar'));",
            "status bar zoom contract",
        ),
        (
            "expect(zoom, contains('onZoomSelected'));",
            "expect(zoom, contains('onZoomChanged'));",
            "numeric zoom callback contract",
        ),
        (
            "expect(zoom, contains('Personalizado…'));",
            "expect(zoom, contains(\"tooltip: 'Ajustar à página'\"));",
            "fit page contract",
        ),
    ],
)

old_chrome_test = """  test('notebook editor chrome is extracted from the screen state', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')
        .readAsStringSync();

    expect(screen, contains(\"import '../widgets/notebook_editor_chrome.dart';\"));
    expect(screen, contains('NotebookNavigationBar('));
    expect(screen, contains('NotebookLayerStatus('));
    expect(screen, contains('NotebookZoomControls('));

    expect(chrome, contains('class NotebookNavigationBar'));
    expect(chrome, contains('class NotebookLayerStatus'));
    expect(chrome, contains('class NotebookZoomControls'));
  });
"""
new_chrome_test = """  test('notebook editor chrome is extracted into the WordPad shell', () {
    final screen = File('lib/src/screens/layered_notebook_screen.dart')
        .readAsStringSync();
    final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart')
        .readAsStringSync();

    expect(screen, contains(\"import '../widgets/notebook_wordpad_chrome.dart';\"));
    expect(screen, contains('NotebookWordPadScaffold('));
    expect(screen, contains('homeRibbon: _buildTextFormattingToolbar()'));
    expect(screen, contains('drawingRibbon: _buildToolbar()'));
    expect(screen, contains('viewRibbon: _buildViewRibbon()'));

    expect(chrome, contains('class NotebookWordPadScaffold'));
    expect(chrome, contains('class NotebookWordPadStatusBar'));
    expect(chrome, contains('class NotebookDocumentRuler'));
    expect(chrome, contains('height: 96'));
    expect(chrome, contains('height: 29'));
  });
"""
patch_file(
    "test/notebook_editor_chrome_contract_test.dart",
    [(old_chrome_test, new_chrome_test, "WordPad shell contract")],
)

patch_file(
    "test/notebook_editor_ux_contract_test.dart",
    [
        (
            "final chrome = File('lib/src/widgets/notebook_editor_chrome.dart')",
            "final chrome = File('lib/src/widgets/notebook_wordpad_chrome.dart')",
            "WordPad chrome source",
        ),
        (
            "expect(screen, contains('NotebookZoomControls('));",
            "expect(screen, contains('NotebookWordPadScaffold('));",
            "WordPad scaffold contract",
        ),
        (
            "expect(chrome, contains(\"tooltip: 'Aumentar zoom'\"));",
            "expect(chrome, contains(\"label: 'Mais'\"));",
            "zoom in command",
        ),
        (
            "expect(chrome, contains(\"tooltip: 'Diminuir zoom'\"));",
            "expect(chrome, contains(\"label: 'Menos'\"));",
            "zoom out command",
        ),
        (
            "expect(chrome, contains(\"tooltip: 'Ajustar página'\"));",
            "expect(chrome, contains(\"tooltip: 'Ajustar à página'\"));",
            "fit page command",
        ),
        (
            "expect(chrome, contains('onZoomSelected'));",
            "expect(chrome, contains('onZoomChanged'));",
            "zoom callback",
        ),
        (
            "expect(chrome, contains('onCustomZoom'));",
            "expect(chrome, contains('NotebookWordPadViewRibbon'));",
            "view ribbon contract",
        ),
        (
            "expect(inkControls, contains(\"label: const Text('Selecionar')\"));",
            "expect(inkControls, contains(\"label: 'Selecionar'\"));",
            "selection command",
        ),
        (
            "expect(inkControls, contains(\"label: const Text('Mão')\"));",
            "expect(inkControls, contains(\"label: 'Mão'\"));",
            "hand command",
        ),
        (
            "expect(objectControls, contains(\"label: const Text('Texto')\"));",
            "expect(objectControls, contains(\"label: 'Texto'\"));",
            "text insertion command",
        ),
        (
            "expect(toolbar, contains('height: 54'));",
            "expect(toolbar, contains('WordPadRibbonGroup('));",
            "ribbon group composition",
        ),
    ],
)

patch_file(
    "test/minimal_notebook_chrome_contract_test.dart",
    [
        (
            "expect(source, contains('height: 54'));",
            "expect(source, contains('WordPadRibbonGroup('));",
            "desktop ribbon contract",
        ),
        (
            "expect(source, contains('surfaceContainerLow.withValues(alpha: 0.72)'));",
            "expect(source, contains(\"label: 'Ferramentas'\"));\n    expect(source, contains(\"label: 'Inserir e objeto'\"));\n    expect(source, contains(\"label: 'Estilo'\"));",
            "ribbon group labels",
        ),
    ],
)

patch_file(
    "test/notebook_object_controls_contract_test.dart",
    [
        (
            "expect(controls, contains(\"label: const Text('Texto')\"));",
            "expect(controls, contains(\"label: 'Texto'\"));",
            "text command",
        ),
        (
            "expect(controls, contains(\"tooltip: 'Inserir forma e selecionar'\"));",
            "expect(controls, contains(\"tooltip: 'Inserir forma'\"));",
            "shape command",
        ),
        (
            "expect(controls, contains(\"tooltip: 'Inserir imagem e selecionar'\"));",
            "expect(controls, contains(\"label: 'Imagem'\"));",
            "image command",
        ),
        (
            "expect(controls, contains(\"tooltip: 'Editar texto selecionado'\"));",
            "expect(controls, contains(\"tooltip: 'Editar texto'\"));",
            "edit text command",
        ),
        (
            "expect(controls, contains(\"label: const Text('Excluir')\"));",
            "expect(controls, contains(\"tooltip: 'Excluir \\${_selectionLabel(selected.type)}'\"));",
            "contextual delete command",
        ),
    ],
)

patch_file(
    "test/notebook_ink_controls_contract_test.dart",
    [
        (
            "expect(controls, contains(\"label: const Text('Selecionar')\"));",
            "expect(controls, contains(\"label: 'Selecionar'\"));",
            "selection command",
        ),
        (
            "expect(controls, contains(\"label: Text('Caneta')\"));",
            "expect(controls, contains(\"label: 'Caneta'\"));",
            "pen command",
        ),
        (
            "expect(controls, contains(\"label: Text('Lápis')\"));",
            "expect(controls, contains(\"label: 'Lápis'\"));",
            "pencil command",
        ),
        (
            "expect(controls, contains(\"label: Text('Marca-texto')\"));",
            "expect(controls, contains(\"label: 'Marca-texto'\"));",
            "highlighter command",
        ),
        (
            "expect(controls, contains(\"label: const Text('Borracha')\"));",
            "expect(controls, contains(\"label: 'Borracha'\"));",
            "eraser command",
        ),
        (
            "expect(controls, contains(\"? 'Laço (\\$selectionCount)' : 'Laço'\"));",
            "expect(controls, contains(\"label: selectionCount > 0 ? 'Laço \\$selectionCount' : 'Laço'\"));",
            "lasso command",
        ),
    ],
)

patch_file(
    "test/notebook_wordpad_editor_contract_test.dart",
    [
        (
            "expect(screen, contains(\"labelText: 'Fonte'\"));",
            "expect(screen, contains(\"label: 'Fonte'\"));",
            "font group",
        ),
        (
            "expect(screen, contains(\"labelText: 'Tamanho'\"));",
            "expect(screen, contains('DropdownButton<double>('));",
            "font size selector",
        ),
    ],
)

patch_file(
    "test/library_notebook_interaction_contract_test.dart",
    [
        (
            "expect(objectControls, contains(\"tooltip: 'Duplicar objeto selecionado'\"));",
            "expect(\n      objectControls,\n      contains(\"tooltip: 'Duplicar \\${_selectionLabel(selected.type)}'\"),\n    );",
            "contextual duplicate command",
        ),
        (
            "expect(objectControls, contains(\"label: const Text('Excluir')\"));",
            "expect(\n      objectControls,\n      contains(\"tooltip: 'Excluir \\${_selectionLabel(selected.type)}'\"),\n    );",
            "contextual delete command",
        ),
    ],
)

print("WordPad v2 schema and source contracts aligned with the production shell.")

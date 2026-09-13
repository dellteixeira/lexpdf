from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def write(rel, text):
    (ROOT / rel).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f'{label}: expected exactly 1 occurrence, found {count}'
        )
    return text.replace(old, new, 1)


# Schema v11 is intentional: rich documents are persisted per notebook page.
path = 'apps/lexpdf_app/test/local_notebook_layer_store_test.dart'
text = read(path)
text = replace_once(
    text,
    "test('schema 10 creates and persists ordered notebook layers', () async {",
    "test('schema 11 creates and persists ordered notebook layers', () async {",
    'layer schema test title',
)
text = replace_once(
    text,
    'expect(database.database.userVersion, 10);',
    'expect(database.database.userVersion, 11);',
    'layer schema version',
)
write(path, text)


# Selection, rich-text editing and Hand navigation are now separate modes.
path = 'apps/lexpdf_app/test/desktop_pdf_notebook_navigation_contract_test.dart'
text = read(path)
text = replace_once(
    text,
    "    expect(screen, contains('_pointerMode && !_handMode && _canEditActiveLayer'));\n",
    (
        "    expect(screen, contains('enabled: _textMode && !_handMode'));\n"
        "    expect(screen, contains('enabled: !_textMode &&'));\n"
        "    expect(screen, contains('_pointerMode &&'));\n"
        "    expect(screen, contains('_canEditActiveLayer,'));\n"
    ),
    'desktop notebook mode contract',
)
write(path, text)


path = 'apps/lexpdf_app/test/notebook_editor_ux_contract_test.dart'
text = read(path)
text = replace_once(
    text,
    (
        '    // Selection remains exclusive with Hand navigation. Text editing uses the\n'
        '    // same object layer and therefore keeps these ownership rules intact.\n'
        "    expect(screen, contains('_pointerMode && !_handMode && _canEditActiveLayer'));\n"
        "    expect(screen, contains('ignoring:'));\n"
        "    expect(screen, contains('!_canEditActiveLayer || _pointerMode || _handMode'));\n"
        "    expect(screen, contains('panEnabled: _handMode'));\n"
        "    expect(screen, contains('scaleEnabled: _handMode'));\n"
    ),
    (
        '    // FluentDocument owns text editing. Object selection and Hand navigation\n'
        '    // remain mutually exclusive, while drawing ignores input during text mode.\n'
        "    expect(screen, contains('_textMode = true'));\n"
        "    expect(screen, contains('enabled: _textMode && !_handMode'));\n"
        "    expect(screen, contains('enabled: !_textMode &&'));\n"
        "    expect(screen, contains('_pointerMode &&'));\n"
        "    expect(screen, contains('ignoring:'));\n"
        "    expect(screen, contains('!_canEditActiveLayer ||'));\n"
        "    expect(screen, contains('_textMode ||'));\n"
        "    expect(screen, contains('panEnabled: _handMode'));\n"
        "    expect(screen, contains('scaleEnabled: _handMode'));\n"
    ),
    'notebook editor rich-mode ownership contract',
)
write(path, text)


# Text is no longer a positioned object. It is one flowing FluentDocument.
path = 'apps/lexpdf_app/test/library_notebook_interaction_contract_test.dart'
text = read(path)
text = replace_once(
    text,
    "    expect(screen, contains('_beginTextEditing(selectedObject)'));\n",
    "    expect(screen, contains('onEditTextObject: _activateTextMode'));\n",
    'library rich text edit action',
)
text = replace_once(
    text,
    "    expect(objectLayer, contains('_InlineNotebookTextEditor'));\n",
    "    expect(objectLayer, isNot(contains('_InlineNotebookTextEditor')));\n",
    'library no inline text editor',
)
text = replace_once(
    text,
    "    expect(screen, contains('_buildTextFormattingToolbar()'));\n",
    (
        "    expect(screen, contains('_buildTextFormattingToolbar()'));\n"
        "    expect(screen, contains('NotebookRichDocumentSurface('));\n"
    ),
    'library rich document surface contract',
)
write(path, text)

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


def replace_exact(text, old, new, expected, label):
    count = text.count(old)
    if count != expected:
        raise RuntimeError(
            f'{label}: expected exactly {expected} occurrences, found {count}'
        )
    return text.replace(old, new)


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


# fluent_editor 1.1.0 is built against archive 3.x. Keep the application's
# backup implementation on the archive 3.6.1 API as well, instead of forcing
# archive 4 and breaking the editor package.
path = 'apps/lexpdf_app/lib/src/core/backup/lex_backup_service.dart'
text = read(path)
text = replace_once(
    text,
    "    archive.addFile(ArchiveFile.bytes('database.json', databaseBytes));\n",
    "    archive.addFile(ArchiveFile('database.json', databaseBytes.length, databaseBytes));\n",
    'backup database archive entry',
)
text = replace_once(
    text,
    "      archive.addFile(ArchiveFile.bytes(archivePath, bytes));\n",
    "      archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));\n",
    'backup document archive entry',
)
text = replace_once(
    text,
    (
        "    archive.addFile(\n"
        "      ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),\n"
        "    );\n"
        "    return ZipEncoder().encodeBytes(archive);\n"
    ),
    (
        "    final manifestBytes = utf8.encode(jsonEncode(manifest));\n"
        "    archive.addFile(\n"
        "      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),\n"
        "    );\n"
        "    return Uint8List.fromList(ZipEncoder().encode(archive)!);\n"
    ),
    'backup manifest and archive encoding',
)
write(path, text)


# archive 3 exposes file streams via archive_io and calls decoder streaming
# input decodeBuffer (renamed to decodeStream in archive 4).
path = 'apps/lexpdf_app/lib/src/core/backup/lex_backup_streaming_restore_service.dart'
text = read(path)
text = replace_once(
    text,
    "import 'package:archive/archive.dart';\n",
    "import 'package:archive/archive_io.dart';\n",
    'streaming backup archive_io import',
)
text = replace_exact(
    text,
    'ZipDecoder().decodeStream(input, verify: true)',
    'ZipDecoder().decodeBuffer(input, verify: true)',
    2,
    'streaming backup decoder API',
)
text = replace_exact(
    text,
    'manifestFile.readBytes()',
    'manifestFile.content as List<int>',
    1,
    'streaming manifest bytes API',
)
text = replace_exact(
    text,
    'databaseFile.readBytes()',
    'databaseFile.content as List<int>',
    1,
    'streaming database bytes API',
)
text = replace_exact(
    text,
    'manifestEntry.readBytes()!',
    'manifestEntry.content as List<int>',
    1,
    'restore manifest bytes API',
)
text = replace_exact(
    text,
    'databaseEntry.readBytes()!',
    'databaseEntry.content as List<int>',
    1,
    'restore database bytes API',
)
write(path, text)


path = 'apps/lexpdf_app/test/squid_import_service_test.dart'
text = read(path)
text = replace_once(
    text,
    "      ..addFile(ArchiveFile.bytes('one/document.pdf', const [1, 2, 3]))\n",
    "      ..addFile(ArchiveFile('one/document.pdf', 3, const [1, 2, 3]))\n",
    'squid archive entry one',
)
text = replace_once(
    text,
    "      ..addFile(ArchiveFile.bytes('two/document.pdf', const [4, 5, 6]));\n",
    "      ..addFile(ArchiveFile('two/document.pdf', 3, const [4, 5, 6]));\n",
    'squid archive entry two',
)
text = replace_once(
    text,
    '    await source.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);\n',
    '    await source.writeAsBytes(ZipEncoder().encode(archive)!, flush: true);\n',
    'squid archive encoder API',
)
write(path, text)

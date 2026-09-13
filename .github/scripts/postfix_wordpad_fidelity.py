from pathlib import Path

screen_path = Path('apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart')
screen = screen_path.read_text().replace('_WordPadLargeAction', 'WordPadLargeAction')

start = screen.find('  Future<void> _showCustomZoomDialog() async {')
end = screen.find('  Widget _buildNotebookNavigation() {', start)
if start >= 0 and end > start:
    screen = screen[:start] + screen[end:]

screen_path.write_text(screen)

layer_test_path = Path('apps/lexpdf_app/test/local_notebook_layer_store_test.dart')
layer_test = layer_test_path.read_text()
layer_test = layer_test.replace(
    "test('schema 9 creates and persists ordered notebook layers'",
    "test('schema 10 creates and persists ordered notebook layers'",
)
layer_test = layer_test.replace(
    'expect(database.database.userVersion, 9);',
    'expect(database.database.userVersion, 10);',
)
layer_test_path.write_text(layer_test)

rich_test_path = Path('apps/lexpdf_app/test/notebook_rich_text_contract_test.dart')
rich_test = rich_test_path.read_text()
rich_test = rich_test.replace(
    "contains('ALTER TABLE notebook_objects ADD COLUMN font_family')",
    "contains('font_family TEXT')",
)
rich_test = rich_test.replace(
    "contains('ALTER TABLE notebook_objects ADD COLUMN font_bold')",
    "contains('font_bold INTEGER')",
)
rich_test = rich_test.replace(
    "contains('ALTER TABLE notebook_objects ADD COLUMN font_italic')",
    "contains('font_italic INTEGER')",
)
rich_test = rich_test.replace(
    "contains('ALTER TABLE notebook_objects ADD COLUMN font_underline')",
    "contains('font_underline INTEGER')",
)
rich_test_path.write_text(rich_test)

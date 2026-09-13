from pathlib import Path

screen_path = Path('apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart')
screen = screen_path.read_text().replace('_WordPadLargeAction', 'WordPadLargeAction')

start = screen.find('  Future<void> _showCustomZoomDialog() async {')
end = screen.find('  Widget _buildNotebookNavigation() {', start)
if start >= 0 and end > start:
    screen = screen[:start] + screen[end:]

screen_path.write_text(screen)

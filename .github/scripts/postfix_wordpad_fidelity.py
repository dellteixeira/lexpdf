from pathlib import Path

screen_path = Path('apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart')
screen = screen_path.read_text().replace('_WordPadLargeAction', 'WordPadLargeAction')
screen_path.write_text(screen)

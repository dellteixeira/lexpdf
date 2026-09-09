import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app boots into the direct workspace library shell', () {
    final app = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(app, contains('LibraryWorkspaceHomeScreen('));
    expect(app, contains('builder: (_) => PdfWorkspaceScreen('));
    expect(app, isNot(contains('MinimalLibrarySectionsScreen(')));
    expect(app, isNot(contains('PdfReaderScreen(')));
    expect(app, isNot(contains('LocalReadingProgressStore')));
    expect(app, isNot(contains('LocalPdfInkStore')));
  });

  test('library document click opens the unified PDF workspace immediately', () {
    final source = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();

    expect(source, contains("_HomeSection.library, Icons.folder_outlined, 'Biblioteca'"));
    expect(source, contains("_HomeSection.recent, Icons.history, 'Recentes'"));
    expect(source, contains("_HomeSection.favorites, Icons.star_border, 'Favoritos'"));
    expect(source, contains("_HomeSection.notebooks, Icons.edit_note_outlined, 'Cadernos'"));
    expect(source, contains("_HomeSection.offline, Icons.offline_pin_outlined, 'Offline'"));
    expect(source, contains("_HomeSection.cloud, Icons.cloud_outlined, 'Nuvem'"));
    expect(source, contains('final canOpen = document.hasLocalPath;'));
    expect(source, contains('onTap: canOpen ? onOpen : null'));
    expect(source, contains('builder: (_) => PdfWorkspaceScreen('));
    expect(source, contains('unawaited(widget.catalog.markOpened(document.id));'));
    expect(source, isNot(contains('PdfReaderScreen(')));
  });

  test('picker opens the workspace without waiting for catalog bookkeeping', () {
    final source = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();

    expect(source, contains('unawaited(_rememberDocument(picked));'));
    expect(source, contains('await _openDocument(picked, recordOpen: false);'));
    expect(source, contains("'Abrir PDF em Trabalhar com PDF'"));
    expect(source, contains("'Abrir em Trabalhar com PDF'"));
  });

  test('recent documents still require a real last-opened timestamp', () {
    final source = File(
      'lib/src/core/storage/local_document_catalog.dart',
    ).readAsStringSync();

    expect(source, contains('Future<List<DocumentRef>> listRecent'));
    expect(source, contains('WHERE last_opened_at IS NOT NULL'));
    expect(source, contains('ORDER BY last_opened_at DESC'));
  });

  test('desktop shell remains bounded and keeps secondary utilities contextual', () {
    final source = File(
      'lib/src/screens/library_workspace_home_screen.dart',
    ).readAsStringSync();

    expect(source, contains('width < 760'));
    expect(source, contains('width: 204'));
    expect(source, contains('maxWidth: 1180'));
    expect(source, contains('PopupMenuButton<_HomeMoreAction>'));
    expect(source, contains("label: 'Conta'"));
    expect(source, contains("label: 'Imprimir PDF'"));
  });
}

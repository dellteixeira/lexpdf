import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recent documents require a real last-opened timestamp', () {
    final source = File(
      'lib/src/core/storage/local_document_catalog.dart',
    ).readAsStringSync();

    expect(source, contains('Future<List<DocumentRef>> listRecent'));
    expect(source, contains('WHERE last_opened_at IS NOT NULL'));
    expect(source, contains('ORDER BY last_opened_at DESC'));
  });

  test('minimal shell exposes cloud as a first-class section', () {
    final source = File(
      'lib/src/screens/minimal_library_sections_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_ShellSection.cloud'));
    expect(source, contains("Icons.cloud_outlined, 'Nuvem'"));
    expect(source, contains("_ShellSection.recent => 'Recentes'"));
    expect(source, contains('widget.catalog.listRecent(limit: 200)'));
    expect(source, contains("action: 'Abrir nuvem'"));
  });

  test('secondary utilities stay behind the overflow menu', () {
    final source = File(
      'lib/src/screens/minimal_library_sections_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_MoreAction.allTools'));
    expect(source, contains('_MoreAction.account'));
    expect(source, contains('_MoreAction.print'));
    expect(source, isNot(contains('_MoreAction.cloud')));
  });

  test('app boots into the first-class section shell', () {
    final source = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(source, contains('MinimalLibrarySectionsScreen('));
    expect(source, isNot(contains('MinimalLibraryScreen(')));
  });
}

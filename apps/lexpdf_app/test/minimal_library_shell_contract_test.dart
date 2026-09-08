import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main app uses the minimal sections shell without floating chrome', () {
    final source = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(source, contains('MinimalLibrarySectionsScreen('));
    expect(source, isNot(contains('FloatingActionButton')));
    expect(source, isNot(contains('Stack(')));
  });

  test('library shell keeps mobile chrome compact and desktop navigation bounded', () {
    final source = File('lib/src/screens/minimal_library_sections_screen.dart')
        .readAsStringSync();

    expect(source, contains('width < 760'));
    expect(source, contains("tooltip: 'Buscar'"));
    expect(source, contains("tooltip: 'Abrir PDF'"));
    expect(source, contains("tooltip: 'Mais opções'"));
    expect(source, contains('width: 204'));
    expect(source, contains('maxWidth: 1180'));
  });

  test('primary destinations stay visible while secondary utilities stay contextual', () {
    final source = File('lib/src/screens/minimal_library_sections_screen.dart')
        .readAsStringSync();

    expect(source, contains("(_ShellSection.cloud, Icons.cloud_outlined, 'Nuvem')"));
    expect(source, contains('PopupMenuButton<_MoreAction>'));
    expect(source, contains("label: 'Todas as ferramentas'"));
    expect(source, contains("label: 'Conta'"));
    expect(source, contains("label: 'Imprimir PDF'"));
    expect(source, isNot(contains("label: 'Nuvem e sincronização'")));
  });

  test('document rows expose only favorite plus navigation affordance', () {
    final source = File('lib/src/screens/minimal_library_sections_screen.dart')
        .readAsStringSync();

    expect(source, contains('class _DocumentRow'));
    expect(source,
        contains("tooltip: document.favorite ? 'Remover favorito' : 'Favoritar'"));
    expect(source, contains('Icons.chevron_right'));
    expect(source, isNot(contains("tooltip: 'Navegação avançada'")));
    expect(source, isNot(contains("tooltip: 'Anotações avançadas'")));
  });
}

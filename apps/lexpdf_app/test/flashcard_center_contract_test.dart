import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flashcards have a discoverable global center from Home and PDF study menu', () {
    final home =
        File('lib/src/screens/library_workspace_home_screen.dart').readAsStringSync();
    final workspace =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final center =
        File('lib/src/screens/flashcard_center_screen.dart').readAsStringSync();

    expect(home, contains('_HomeSection.flashcards'));
    expect(home, contains("Icons.style_outlined, 'Flashcards'"));
    expect(home, contains('FlashcardCenterScreen'));
    expect(workspace, contains("'Central de Flashcards'"));
    expect(workspace, contains("case 'flashcards'"));
    expect(center, contains('Central de Flashcards'));
    expect(center, contains('Pesquisar todos os flashcards'));
  });

  test('flashcard center exposes hierarchy counts filters and source navigation', () {
    final center =
        File('lib/src/screens/flashcard_center_screen.dart').readAsStringSync();
    final store =
        File('lib/src/core/storage/local_advanced_study_store.dart').readAsStringSync();
    final menu =
        File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();

    expect(center, contains("'Cartões'"));
    expect(center, contains("'Para revisar'"));
    expect(center, contains("'Novos'"));
    expect(center, contains("'Difíceis'"));
    expect(center, contains("'Todas as matérias'"));
    expect(center, contains('entry.topic'));
    expect(center, contains("'Organizar flashcard'"));
    expect(center, contains("'Abrir fonte'"));
    expect(center, contains("'Revisar agora ·"));
    expect(store, contains('listFlashcardEntries'));
    expect(store, contains('updateFlashcardClassification'));
    expect(store, contains('flashcardLibraryStats'));
    expect(menu, contains("labelText: 'Matéria (opcional)'"));
    expect(menu, contains("labelText: 'Assunto (opcional)'"));
    expect(
      menu,
      contains('Encontre-o em Flashcards na tela inicial.'),
    );
  });
}

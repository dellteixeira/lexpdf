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
    expect(center, contains("'Pastas'"));
    expect(center, contains('entry.topic'));
    expect(center, contains("'Organizar flashcard'"));
    expect(center, contains("'Abrir fonte'"));
    expect(center, contains("'Revisar agora ·"));
    expect(store, contains('listFlashcardEntries'));
    expect(store, contains('updateFlashcardClassification'));
    expect(store, contains('flashcardLibraryStats'));
    expect(menu, contains('FlashcardOrganizationFields'));
    expect(
      menu,
      contains('FlashcardOrganizationCatalog.fromEntries'),
    );
    expect(
      menu,
      contains('Encontre-o em Flashcards na tela inicial.'),
    );
  });

  test('flashcard folders can be renamed and created during card save', () {
    final center =
        File('lib/src/screens/flashcard_center_screen.dart').readAsStringSync();
    final store =
        File('lib/src/core/storage/local_advanced_study_store.dart').readAsStringSync();
    final organizer =
        File('lib/src/widgets/flashcard_organization_fields.dart').readAsStringSync();
    final ai =
        File('lib/src/screens/ai_selection_explanation_screen.dart').readAsStringSync();

    expect(center, contains("'Renomear pasta'"));
    expect(center, contains("'Renomear subpasta'"));
    expect(center, contains('_renameSubject'));
    expect(center, contains('_renameTopic'));
    expect(store, contains('renameFlashcardSubject'));
    expect(store, contains('renameFlashcardTopic'));
    expect(organizer, contains("'Pasta / matéria"));
    expect(organizer, contains("'Subpasta / assunto"));
    expect(
      organizer,
      contains('ele será criado ao salvar o cartão'),
    );
    expect(ai, contains('FlashcardOrganizationFields'));
    expect(ai, contains('subject: edited.subject'));
    expect(ai, contains('topic: edited.topic'));
  });
}

import 'package:flutter/material.dart';

import '../core/study/advanced_study_models.dart';

/// Two-level organization used by the flashcard library.
///
/// A broad folder maps to a subject (Matéria) and a subfolder maps to a topic
/// (Assunto). Tags remain independent so a card can still participate in
/// cross-cutting searches without multiplying folders.
class FlashcardOrganizationCatalog {
  const FlashcardOrganizationCatalog({
    required this.subjects,
    required this.topicsBySubject,
  });

  factory FlashcardOrganizationCatalog.fromEntries(
    Iterable<FlashcardLibraryEntry> entries,
  ) {
    final subjects = <String>{};
    final topics = <String, Set<String>>{};
    for (final entry in entries) {
      final subject = entry.subject.trim();
      final topic = entry.topic.trim();
      if (subject.isEmpty) continue;
      subjects.add(subject);
      if (topic.isNotEmpty) {
        topics.putIfAbsent(subject, () => <String>{}).add(topic);
      }
    }

    final orderedSubjects = subjects.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final orderedTopics = <String, List<String>>{};
    for (final entry in topics.entries) {
      final values = entry.value.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      orderedTopics[entry.key] = values;
    }

    return FlashcardOrganizationCatalog(
      subjects: orderedSubjects,
      topicsBySubject: orderedTopics,
    );
  }

  final List<String> subjects;
  final Map<String, List<String>> topicsBySubject;

  List<String> topicsFor(String subject) {
    final normalized = subject.trim().toLowerCase();
    for (final entry in topicsBySubject.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    final all = topicsBySubject.values.expand((value) => value).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return all;
  }
}

/// Shared organization editor for every flashcard creation/editing flow.
///
/// DropdownMenu remains editable: selecting an existing folder is quick, while
/// typing a new name creates that logical folder as soon as the flashcard is
/// saved.
class FlashcardOrganizationFields extends StatefulWidget {
  const FlashcardOrganizationFields({
    required this.subjectController,
    required this.topicController,
    required this.catalog,
    this.optional = true,
    super.key,
  });

  final TextEditingController subjectController;
  final TextEditingController topicController;
  final FlashcardOrganizationCatalog catalog;
  final bool optional;

  @override
  State<FlashcardOrganizationFields> createState() =>
      _FlashcardOrganizationFieldsState();
}

class _FlashcardOrganizationFieldsState
    extends State<FlashcardOrganizationFields> {
  @override
  void initState() {
    super.initState();
    widget.subjectController.addListener(_subjectChanged);
  }

  @override
  void didUpdateWidget(covariant FlashcardOrganizationFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.subjectController, widget.subjectController)) {
      oldWidget.subjectController.removeListener(_subjectChanged);
      widget.subjectController.addListener(_subjectChanged);
    }
  }

  @override
  void dispose() {
    widget.subjectController.removeListener(_subjectChanged);
    super.dispose();
  }

  void _subjectChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final suffix = widget.optional ? ' (opcional)' : '';
    final topics =
        widget.catalog.topicsFor(widget.subjectController.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_copy_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'Organização',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Use pastas para matérias amplas, subpastas para assuntos e tags '
          'para recortes que cruzam várias matérias.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          controller: widget.subjectController,
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          leadingIcon: const Icon(Icons.folder_outlined),
          label: Text('Pasta / matéria$suffix'),
          hintText: 'Escolha ou digite uma nova pasta',
          dropdownMenuEntries: [
            for (final subject in widget.catalog.subjects)
              DropdownMenuEntry<String>(
                value: subject,
                label: subject,
                leadingIcon: const Icon(Icons.folder_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          controller: widget.topicController,
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          leadingIcon: const Icon(Icons.folder_open_outlined),
          label: Text('Subpasta / assunto$suffix'),
          hintText: 'Escolha ou digite uma nova subpasta',
          dropdownMenuEntries: [
            for (final topic in topics)
              DropdownMenuEntry<String>(
                value: topic,
                label: topic,
                leadingIcon: const Icon(Icons.folder_open_outlined),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Se o nome ainda não existir, ele será criado ao salvar o cartão.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

enum StudyItemKind { flashcard, question, explanation, summary }

enum StudyReviewGrade { again, hard, good, easy }

enum FlashcardLibraryFilter { all, due, newCards, difficult }


class StudyItem {
  const StudyItem({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.createdAt,
    required this.updatedAt,
    this.notebookId,
    this.documentId,
    this.documentTitle,
    this.sourcePage,
    this.sourceText = '',
    this.subject = '',
    this.topic = '',
    this.tags = const [],
    this.difficulty = 3,
    this.commentary = '',
  });

  final String id;
  final StudyItemKind kind;
  final String prompt;
  final String answer;
  final String? notebookId;
  final String? documentId;
  final String? documentTitle;
  final int? sourcePage;
  final String sourceText;
  final String subject;
  final String topic;
  final List<String> tags;
  final int difficulty;
  final String commentary;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class StudyReviewState {
  const StudyReviewState({
    required this.itemId,
    required this.dueAt,
    required this.intervalDays,
    required this.easeFactor,
    required this.repetitions,
    required this.lapses,
    this.lastGrade,
    this.lastReviewedAt,
  });

  final String itemId;
  final DateTime dueAt;
  final double intervalDays;
  final double easeFactor;
  final int repetitions;
  final int lapses;
  final StudyReviewGrade? lastGrade;
  final DateTime? lastReviewedAt;
}

class StudyDashboardStats {
  const StudyDashboardStats({
    required this.totalItems,
    required this.dueItems,
    required this.reviewedToday,
    required this.correctToday,
    required this.streakDays,
  });

  final int totalItems;
  final int dueItems;
  final int reviewedToday;
  final int correctToday;
  final int streakDays;

  double get accuracyToday =>
      reviewedToday == 0 ? 0 : correctToday / reviewedToday;
}

class StudySourceHit {
  const StudySourceHit({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.snippet,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final String snippet;
}


class FlashcardLibraryEntry {
  const FlashcardLibraryEntry({
    required this.item,
    required this.review,
  });

  final StudyItem item;
  final StudyReviewState review;

  bool get isDue => !review.dueAt.isAfter(DateTime.now().toUtc());
  bool get isNew => review.repetitions == 0;
  bool get isDifficult =>
      review.lapses > 0 ||
      review.lastGrade == StudyReviewGrade.again ||
      review.lastGrade == StudyReviewGrade.hard;

  String get subject {
    final explicit = item.subject.trim();
    if (explicit.isNotEmpty) return explicit;
    final document = item.documentTitle?.trim() ?? '';
    if (document.isNotEmpty) return document;
    return 'Sem matéria';
  }

  String get topic {
    final explicit = item.topic.trim();
    if (explicit.isNotEmpty) return explicit;
    if (item.tags.isNotEmpty && item.tags.first.trim().isNotEmpty) {
      return item.tags.first.trim();
    }
    return 'Geral';
  }
}

class FlashcardLibraryStats {
  const FlashcardLibraryStats({
    required this.total,
    required this.due,
    required this.newCards,
    required this.difficult,
  });

  final int total;
  final int due;
  final int newCards;
  final int difficult;
}

class AiPreparedInput {
  const AiPreparedInput({
    required this.text,
    required this.itemCount,
    required this.truncated,
  });

  final String text;
  final int itemCount;
  final bool truncated;
}

class AiInputPolicy {
  const AiInputPolicy({
    this.maxCharacters = 100000,
    this.maxItems = 20,
  });

  final int maxCharacters;
  final int maxItems;

  AiPreparedInput prepare(String text, int itemCount) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      throw ArgumentError('O texto de origem está vazio.');
    }
    final safeCount = itemCount.clamp(1, maxItems);
    final truncated = normalized.length > maxCharacters;
    return AiPreparedInput(
      text: truncated ? normalized.substring(0, maxCharacters) : normalized,
      itemCount: safeCount,
      truncated: truncated,
    );
  }
}

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';

class NotebookCoverCard extends StatelessWidget {
  const NotebookCoverCard({
    required this.cover,
    required this.title,
    this.subtitle,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final InkNotebookCover cover;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  static List<Color> colorsFor(InkNotebookCover cover) => switch (cover) {
        InkNotebookCover.midnight => const [
            Color(0xFF151A27),
            Color(0xFF29304A),
          ],
        InkNotebookCover.cobalt => const [
            Color(0xFF183C8B),
            Color(0xFF2E6BE6),
          ],
        InkNotebookCover.ocean => const [
            Color(0xFF005D78),
            Color(0xFF0B8FA8),
          ],
        InkNotebookCover.teal => const [
            Color(0xFF00685F),
            Color(0xFF16A394),
          ],
        InkNotebookCover.forest => const [
            Color(0xFF1E5631),
            Color(0xFF4C8B54),
          ],
        InkNotebookCover.sand => const [
            Color(0xFF9B7446),
            Color(0xFFD3B17C),
          ],
        InkNotebookCover.terracotta => const [
            Color(0xFF8B412E),
            Color(0xFFC66B4D),
          ],
        InkNotebookCover.coral => const [
            Color(0xFFB24545),
            Color(0xFFE27373),
          ],
        InkNotebookCover.wine => const [
            Color(0xFF5B1930),
            Color(0xFF8A2D4D),
          ],
        InkNotebookCover.lavender => const [
            Color(0xFF655187),
            Color(0xFF9983BC),
          ],
        InkNotebookCover.graphite => const [
            Color(0xFF353A40),
            Color(0xFF606871),
          ],
        InkNotebookCover.sky => const [
            Color(0xFF3F79B8),
            Color(0xFF7DB5E8),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final colors = colorsFor(cover);
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.16),
          width: selected ? 3 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 7),
            color: Color(0x24000000),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Container(
              width: 7,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 24, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_stories_outlined,
                  color: Colors.white70,
                  size: 23,
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (selected)
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

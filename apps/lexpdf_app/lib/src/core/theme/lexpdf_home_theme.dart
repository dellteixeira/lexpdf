import 'package:flutter/material.dart';

/// Reader-aligned presentation for the home subtree only.
/// Retains the app's sizing, density, font family and interaction states.
abstract final class LexPdfHomeTheme {
  static ThemeData from(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final surface = Color(dark ? 0xFF222731 : 0xFFFBFCFE);
    final muted = Color(dark ? 0xFF29313D : 0xFFF1F4F8);
    final foreground = Color(dark ? 0xFFEDF0F5 : 0xFF222A36);
    final secondary = Color(dark ? 0xFFB0BAC8 : 0xFF596577);
    final accent = Color(dark ? 0xFFB4CFFF : 0xFF244F92);
    final selected = Color(dark ? 0xFF314563 : 0xFFE6EFFC);
    final outline = Color(dark ? 0xFF394354 : 0xFFDCE2E9);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: dark ? surface : Colors.white,
      primaryContainer: selected,
      onPrimaryContainer: accent,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: secondary,
      surfaceContainerLowest: surface,
      surfaceContainerLow: muted,
      surfaceContainer: muted,
      surfaceContainerHigh: muted,
      surfaceContainerHighest: muted,
      outline: outline,
      outlineVariant: outline,
    );
    final text = base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF1B2029)
          : base.scaffoldBackgroundColor,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: surface,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w500,
        ),
        iconTheme: base.appBarTheme.iconTheme?.copyWith(color: secondary),
        actionsIconTheme:
            base.appBarTheme.actionsIconTheme?.copyWith(color: secondary),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: outline.withValues(alpha: 0.8),
      ),
      iconTheme: base.iconTheme.copyWith(color: secondary),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outline.withValues(alpha: 0.75)),
        ),
      ),
      drawerTheme: base.drawerTheme.copyWith(backgroundColor: surface),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: secondary,
        textColor: foreground,
        selectedColor: accent,
        selectedTileColor: selected,
        titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
          color: foreground,
        ),
        subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
          color: secondary,
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: surface,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outline),
        ),
      ),
    );
  }
}

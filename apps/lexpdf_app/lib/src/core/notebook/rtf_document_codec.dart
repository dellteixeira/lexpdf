import 'dart:convert';
import 'dart:typed_data';

class RtfDocumentCodec {
  const RtfDocumentCodec();

  String decodeToHtml(Uint8List bytes) {
    if (bytes.isEmpty) return '<p></p>';
    final source = latin1.decode(bytes, allowInvalid: true);
    final stack = <_RtfState>[];
    var state = const _RtfState();
    final html = StringBuffer('<p>');
    final text = StringBuffer();
    var skipFallback = 0;

    void flush() {
      if (text.isEmpty || state.ignored) {
        text.clear();
        return;
      }
      var value = _escapeHtml(text.toString());
      if (state.bold) value = '<strong>$value</strong>';
      if (state.italic) value = '<em>$value</em>';
      if (state.underline) value = '<u>$value</u>';
      if (state.strike) value = '<s>$value</s>';
      if (state.fontSizeHalfPoints != 24) {
        final points = state.fontSizeHalfPoints / 2;
        value = '<span style="font-size:${points.toStringAsFixed(points % 1 == 0 ? 0 : 1)}pt">$value</span>';
      }
      html.write(value);
      text.clear();
    }

    void paragraph() {
      flush();
      if (!state.ignored) html.write('</p><p>');
    }

    var index = 0;
    while (index < source.length) {
      final char = source[index];
      if (char == '{') {
        flush();
        stack.add(state);
        state = state.copyWith();
        index++;
        continue;
      }
      if (char == '}') {
        flush();
        if (stack.isNotEmpty) state = stack.removeLast();
        index++;
        continue;
      }
      if (char != r'\') {
        if (!state.ignored) {
          if (skipFallback > 0) {
            skipFallback--;
          } else if (char != '\r' && char != '\n') {
            text.write(char);
          }
        }
        index++;
        continue;
      }

      flush();
      index++;
      if (index >= source.length) break;
      final next = source[index];
      if (next == r'\' || next == '{' || next == '}') {
        if (!state.ignored) {
          if (skipFallback > 0) {
            skipFallback--;
          } else {
            text.write(next);
          }
        }
        index++;
        continue;
      }
      if (next == "'") {
        if (index + 2 < source.length) {
          final hex = source.substring(index + 1, index + 3);
          final value = int.tryParse(hex, radix: 16);
          if (!state.ignored && value != null) {
            if (skipFallback > 0) {
              skipFallback--;
            } else {
              text.write(_windows1252(value));
            }
          }
          index += 3;
        } else {
          index++;
        }
        continue;
      }
      if (next == '*') {
        state = state.copyWith(ignored: true);
        index++;
        continue;
      }
      if (next == '~') {
        if (!state.ignored) text.write('\u00A0');
        index++;
        continue;
      }
      if (next == '_') {
        if (!state.ignored) text.write('\u2011');
        index++;
        continue;
      }
      if (next == '-') {
        index++;
        continue;
      }

      final wordStart = index;
      while (index < source.length &&
          RegExp(r'[A-Za-z]').hasMatch(source[index])) {
        index++;
      }
      final word = source.substring(wordStart, index).toLowerCase();
      var sign = 1;
      if (index < source.length && source[index] == '-') {
        sign = -1;
        index++;
      }
      final numberStart = index;
      while (index < source.length &&
          RegExp(r'[0-9]').hasMatch(source[index])) {
        index++;
      }
      final hasNumber = index > numberStart;
      final number = hasNumber
          ? sign * (int.tryParse(source.substring(numberStart, index)) ?? 0)
          : null;
      if (index < source.length && source[index] == ' ') index++;

      const destinations = {
        'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object',
        'header', 'headerl', 'headerr', 'footer', 'footerl', 'footerr',
        'generator', 'filetbl', 'revtbl', 'xmlnstbl', 'listtable',
        'listoverridetable', 'themedata', 'datastore',
      };
      if (destinations.contains(word)) {
        state = state.copyWith(ignored: true);
        continue;
      }
      if (state.ignored) continue;

      switch (word) {
        case 'par':
          paragraph();
          break;
        case 'line':
          text.write('\n');
          break;
        case 'tab':
          text.write('\t');
          break;
        case 'b':
          state = state.copyWith(bold: number != 0);
          break;
        case 'i':
          state = state.copyWith(italic: number != 0);
          break;
        case 'ul':
          state = state.copyWith(underline: number != 0);
          break;
        case 'ulnone':
          state = state.copyWith(underline: false);
          break;
        case 'strike':
          state = state.copyWith(strike: number != 0);
          break;
        case 'plain':
          state = state.copyWith(
            bold: false,
            italic: false,
            underline: false,
            strike: false,
            fontSizeHalfPoints: 24,
          );
          break;
        case 'fs':
          if (number != null && number > 0) {
            state = state.copyWith(fontSizeHalfPoints: number);
          }
          break;
        case 'uc':
          if (number != null && number >= 0 && number <= 8) {
            state = state.copyWith(unicodeSkip: number);
          }
          break;
        case 'u':
          if (number != null) {
            var code = number;
            if (code < 0) code += 65536;
            text.writeCharCode(code);
            skipFallback = state.unicodeSkip;
          }
          break;
      }
    }
    flush();
    html.write('</p>');
    return html.toString();
  }

  Uint8List encodeHtml(String html) {
    final cleanedHtml = html.replaceAll(
      RegExp(r'<head\b[\s\S]*?</head>', caseSensitive: false),
      '',
    );
    final out = StringBuffer(r'{\rtf1\ansi\ansicpg1252\deff0');
    out.write(r'{\fonttbl{\f0 Arial;}}');
    out.write(r'\viewkind4\uc1\pard\f0\fs24 ');
    final stack = <_HtmlState>[const _HtmlState()];
    var state = stack.last;
    final tokens = RegExp(r'<[^>]*>|[^<]+', multiLine: true)
        .allMatches(cleanedHtml)
        .map((match) => match.group(0)!)
        .toList(growable: false);

    void transition(_HtmlState from, _HtmlState to) {
      if (from.bold != to.bold) out.write(to.bold ? r'\b ' : r'\b0 ');
      if (from.italic != to.italic) out.write(to.italic ? r'\i ' : r'\i0 ');
      if (from.underline != to.underline) {
        out.write(to.underline ? r'\ul ' : r'\ulnone ');
      }
      if (from.strike != to.strike) {
        out.write(to.strike ? r'\strike ' : r'\strike0 ');
      }
      if (from.fontSizeHalfPoints != to.fontSizeHalfPoints) {
        out.write('\\fs${to.fontSizeHalfPoints} ');
      }
    }

    for (final token in tokens) {
      if (!token.startsWith('<')) {
        out.write(_rtfEscape(_decodeHtmlEntities(token)));
        continue;
      }
      final lower = token.toLowerCase();
      if (lower.startsWith('<!--') ||
          lower.startsWith('<!doctype') ||
          lower.startsWith('<html') ||
          lower.startsWith('</html') ||
          lower.startsWith('<head') ||
          lower.startsWith('</head') ||
          lower.startsWith('<style')) {
        continue;
      }
      if (lower.startsWith('</style')) continue;
      if (lower == '<br>' || lower == '<br/>' || lower == '<br />') {
        out.write(r'\line ');
        continue;
      }
      if (lower.startsWith('<img')) {
        out.write(_rtfEscape('[Imagem]'));
        continue;
      }
      if (lower.startsWith('<hr')) {
        out.write(r'\par --------------------\par ');
        continue;
      }
      if (RegExp(r'^</(p|div|h[1-6]|blockquote|pre|li|tr)').hasMatch(lower)) {
        out.write(r'\par ');
      }
      if (RegExp(r'^</(td|th)').hasMatch(lower)) {
        out.write(r'\tab ');
      }

      if (lower.startsWith('</')) {
        if (stack.length > 1) {
          final previous = state;
          stack.removeLast();
          state = stack.last;
          transition(previous, state);
        }
        continue;
      }

      var next = state;
      final tag = RegExp(r'^<\s*([a-z0-9]+)').firstMatch(lower)?.group(1) ?? '';
      switch (tag) {
        case 'b':
        case 'strong':
          next = next.copyWith(bold: true);
          break;
        case 'i':
        case 'em':
          next = next.copyWith(italic: true);
          break;
        case 'u':
          next = next.copyWith(underline: true);
          break;
        case 's':
        case 'del':
          next = next.copyWith(strike: true);
          break;
        case 'h1':
          next = next.copyWith(bold: true, fontSizeHalfPoints: 36);
          break;
        case 'h2':
          next = next.copyWith(bold: true, fontSizeHalfPoints: 32);
          break;
        case 'h3':
          next = next.copyWith(bold: true, fontSizeHalfPoints: 28);
          break;
        case 'h4':
          next = next.copyWith(bold: true, fontSizeHalfPoints: 26);
          break;
        case 'h5':
        case 'h6':
          next = next.copyWith(bold: true, fontSizeHalfPoints: 24);
          break;
        case 'span':
          final style =
              RegExp(r"""style\s*=\s*["']([^"']*)""").firstMatch(token)?.group(1);
          if (style != null) next = _stateFromCss(next, style);
          break;
      }
      if (lower.startsWith('<li')) out.write(r'\bullet\tab ');
      stack.add(next);
      transition(state, next);
      state = next;
      if (lower.endsWith('/>')) {
        final previous = state;
        stack.removeLast();
        state = stack.last;
        transition(previous, state);
      }
    }

    out.write('}');
    return Uint8List.fromList(latin1.encode(out.toString()));
  }

  static _HtmlState _stateFromCss(_HtmlState state, String css) {
    var next = state;
    final lower = css.toLowerCase();
    if (lower.contains('font-weight: bold') ||
        RegExp(r'font-weight\s*:\s*[6-9]00').hasMatch(lower)) {
      next = next.copyWith(bold: true);
    }
    if (lower.contains('font-style: italic')) {
      next = next.copyWith(italic: true);
    }
    if (lower.contains('text-decoration') && lower.contains('underline')) {
      next = next.copyWith(underline: true);
    }
    if (lower.contains('text-decoration') &&
        lower.contains('line-through')) {
      next = next.copyWith(strike: true);
    }
    final sizeMatch =
        RegExp(r'font-size\s*:\s*([0-9.]+)(px|pt)').firstMatch(lower);
    if (sizeMatch != null) {
      final raw = double.tryParse(sizeMatch.group(1) ?? '');
      if (raw != null && raw > 0) {
        final points = sizeMatch.group(2) == 'px' ? raw * 0.75 : raw;
        next = next.copyWith(fontSizeHalfPoints: (points * 2).round());
      }
    }
    return next;
  }

  static String _rtfEscape(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 0x5C) {
        buffer.write(r'\\');
      } else if (rune == 0x7B) {
        buffer.write(r'\{');
      } else if (rune == 0x7D) {
        buffer.write(r'\}');
      } else if (rune == 0x0A) {
        buffer.write(r'\line ');
      } else if (rune == 0x09) {
        buffer.write(r'\tab ');
      } else if (rune >= 0x20 && rune <= 0x7E) {
        buffer.writeCharCode(rune);
      } else if (rune <= 0xFFFF) {
        final signed = rune > 32767 ? rune - 65536 : rune;
        buffer.write('\\u$signed?');
      } else {
        final value = rune - 0x10000;
        final high = 0xD800 + (value >> 10);
        final low = 0xDC00 + (value & 0x3FF);
        buffer.write('\\u${high - 65536}?\\u${low - 65536}?');
      }
    }
    return buffer.toString();
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _decodeHtmlEntities(String value) => value
      .replaceAll('&nbsp;', '\u00A0')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  static String _windows1252(int value) {
    const mapping = <int, int>{
      0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
      0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
      0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
      0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
      0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
      0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
      0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    };
    return String.fromCharCode(mapping[value] ?? value);
  }
}

class _RtfState {
  const _RtfState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSizeHalfPoints = 24,
    this.unicodeSkip = 1,
    this.ignored = false,
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final int fontSizeHalfPoints;
  final int unicodeSkip;
  final bool ignored;

  _RtfState copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    int? fontSizeHalfPoints,
    int? unicodeSkip,
    bool? ignored,
  }) => _RtfState(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        fontSizeHalfPoints: fontSizeHalfPoints ?? this.fontSizeHalfPoints,
        unicodeSkip: unicodeSkip ?? this.unicodeSkip,
        ignored: ignored ?? this.ignored,
      );
}

class _HtmlState {
  const _HtmlState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSizeHalfPoints = 24,
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final int fontSizeHalfPoints;

  _HtmlState copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    int? fontSizeHalfPoints,
  }) => _HtmlState(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        fontSizeHalfPoints: fontSizeHalfPoints ?? this.fontSizeHalfPoints,
      );
}

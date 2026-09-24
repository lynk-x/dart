import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lynk_x/presentation/features/forum/core/forum_config.dart';

/// A widget that parses and renders message text, styling and making clickable:
/// 1. User mentions (@username)
/// 2. Web URLs
/// 3. Simple lists — lines starting with "- "/"* " (bulleted) or "1. "
///    (numbered) render with a real bullet/number and hanging indent,
///    instead of the literal marker text.
class ParsedMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color accentColor;
  final Function(String username)? onMentionTap;
  final Function(String url)? onUrlTap;
  final bool isEdited;

  const ParsedMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.accentColor,
    this.onMentionTap,
    this.onUrlTap,
    this.isEdited = false,
  });

  @override
  State<ParsedMessageText> createState() => _ParsedMessageTextState();
}

// A bulleted ("- "/"* ") or numbered ("1. ", "2. ", ...) list-item line.
// null marker text + non-null number means numbered; non-null marker with
// null number means bulleted.
class _ListLine {
  final String marker; // "•" for bulleted, "1", "2", ... for numbered
  final bool isNumbered;
  final String content;
  const _ListLine({required this.marker, required this.isNumbered, required this.content});
}

final RegExp _bulletLineRegex = RegExp(r'^[ \t]*[-*][ \t]+(.*)$');
final RegExp _numberedLineRegex = RegExp(r'^[ \t]*(\d+)\.[ \t]+(.*)$');

_ListLine? _matchListLine(String line) {
  final bulletMatch = _bulletLineRegex.firstMatch(line);
  if (bulletMatch != null) {
    return _ListLine(marker: '•', isNumbered: false, content: bulletMatch.group(1)!);
  }
  final numberedMatch = _numberedLineRegex.firstMatch(line);
  if (numberedMatch != null) {
    return _ListLine(
      marker: numberedMatch.group(1)!,
      isNumbered: true,
      content: numberedMatch.group(2)!,
    );
  }
  return null;
}

class _ParsedMessageTextState extends State<ParsedMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Parses [text] for @mentions and URLs, returning inline spans styled
  /// and made tappable — the same entity parsing previously applied to the
  /// whole message at once, now reused per-line so it still applies inside
  /// list items.
  List<InlineSpan> _parseInlineSpans(String text) {
    final combinedRegex = RegExp(
      r'((?:https?|ftp)://[^\s/$.?#].[^\s]*|[a-zA-Z0-9][\w\-]*(?:[\w/\-?=%]*\.[\w/\-?=%]+)+|@\w+)',
      caseSensitive: false,
    );

    final matches = combinedRegex.allMatches(text);
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: widget.style)];
    }

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: widget.style,
        ));
      }

      final token = match.group(0)!;
      if (token.startsWith('@')) {
        final username = token.substring(1);

        final isPrecededByWordChar = match.start > 0 &&
            RegExp(r'\w').hasMatch(text.substring(match.start - 1, match.start));

        if (isPrecededByWordChar) {
          spans.add(TextSpan(text: token, style: widget.style));
        } else {
          final recognizer = TapGestureRecognizer()
            ..onTap = () => widget.onMentionTap?.call(username);
          _recognizers.add(recognizer);

          spans.add(TextSpan(
            text: token,
            style: widget.style.copyWith(
              color: widget.accentColor,
              fontWeight: FontWeight.bold,
            ),
            recognizer: recognizer,
          ));
        }
      } else {
        final validUrl = token.startsWith('http') ? token : 'https://$token';
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onUrlTap?.call(validUrl);
        _recognizers.add(recognizer);

        spans.add(TextSpan(
          text: token,
          style: widget.style.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: widget.style.color,
          ),
          recognizer: recognizer,
        ));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: widget.style));
    }

    return spans;
  }

  TextStyle get _editedSuffixStyle => widget.style.copyWith(
        color: widget.style.color?.withValues(alpha: 0.4) ?? Colors.white38,
        fontSize: (widget.style.fontSize ?? 14) - 2,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.normal,
      );

  Widget _buildEditedSuffix() => Text(' [edited]', style: _editedSuffixStyle);

  @override
  Widget build(BuildContext context) {
    // DoS Safeguard: Fallback to plain text rendering for oversized payloads
    // (>5,000 chars) — no line/list parsing either, same as before.
    if (widget.text.length > ForumConfig.maxRegexScanLength) {
      if (widget.isEdited) {
        return Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text(widget.text, style: widget.style),
          _buildEditedSuffix(),
        ]);
      }
      return Text(widget.text, style: widget.style);
    }

    final lines = widget.text.split('\n');
    final hasListLine = lines.any((l) => _matchListLine(l) != null);

    if (!hasListLine) {
      // No list lines at all — render as one flat Text.rich, same as
      // before (this is the common case: plain messages, with or without
      // mentions/URLs, still get a single paragraph, not one row per line).
      final spans = _parseInlineSpans(widget.text);
      if (widget.isEdited) spans.add(TextSpan(text: ' [edited]', style: _editedSuffixStyle));
      return Text.rich(TextSpan(children: spans));
    }

    // At least one list line — build a column of paragraph blocks and list
    // rows, in order, so list items get real bullet/number + indent
    // treatment while surrounding plain text still reads as normal
    // paragraphs.
    final widgets = <Widget>[];
    final paragraphBuffer = StringBuffer();

    void flushParagraph() {
      if (paragraphBuffer.isEmpty) return;
      final text = paragraphBuffer.toString();
      paragraphBuffer.clear();
      widgets.add(Text.rich(TextSpan(children: _parseInlineSpans(text))));
    }

    for (final line in lines) {
      final listLine = _matchListLine(line);
      if (listLine == null) {
        if (paragraphBuffer.isNotEmpty) paragraphBuffer.write('\n');
        paragraphBuffer.write(line);
        continue;
      }
      flushParagraph();
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: listLine.isNumbered ? 20 : 14,
              child: Text(
                listLine.isNumbered ? '${listLine.marker}.' : listLine.marker,
                style: widget.style,
              ),
            ),
            Expanded(
              child: Text.rich(TextSpan(children: _parseInlineSpans(listLine.content))),
            ),
          ],
        ),
      ));
    }
    flushParagraph();

    if (widget.isEdited && widgets.isNotEmpty) {
      widgets.add(_buildEditedSuffix());
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

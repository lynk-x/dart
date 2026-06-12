import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A widget that parses and renders message text, styling and making clickable:
/// 1. User mentions (@username)
/// 2. Web URLs
class ParsedMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color accentColor;
  final Function(String username)? onMentionTap;
  final Function(String url)? onUrlTap;

  const ParsedMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.accentColor,
    this.onMentionTap,
    this.onUrlTap,
  });

  @override
  State<ParsedMessageText> createState() => _ParsedMessageTextState();
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

  @override
  Widget build(BuildContext context) {
    // Regex matching either URLs or mentions
    final combinedRegex = RegExp(
      r'((?:https?|ftp)://[^\s/$.?#].[^\s]*|[\w/\-?=%.]+\.[\w/\-?=%.]+|@\w+)',
      caseSensitive: false,
    );

    final matches = combinedRegex.allMatches(widget.text);
    if (matches.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: widget.text.substring(lastIndex, match.start),
          style: widget.style,
        ));
      }

      final token = match.group(0)!;
      if (token.startsWith('@')) {
        // Option A: Renders mention as bold, accent-colored clickable text
        final username = token.substring(1);

        // Verify it is not preceded by an alphanumeric/word character to avoid matching in emails
        final isPrecededByWordChar = match.start > 0 &&
            RegExp(r'\w').hasMatch(
                widget.text.substring(match.start - 1, match.start));

        if (isPrecededByWordChar) {
          spans.add(TextSpan(
            text: token,
            style: widget.style,
          ));
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
        // Renders URL as underlined clickable text
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

    if (lastIndex < widget.text.length) {
      spans.add(TextSpan(
        text: widget.text.substring(lastIndex),
        style: widget.style,
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

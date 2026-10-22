class EmbeddingNoiseFilter {
  // Unicode-property based, not a hardcoded Latin/Latin-Extended range \u2014
  // the embedding model is multilingual, so "meaningful content" shouldn't
  // be defined as "has a Latin letter." \p{L} = any letter, \p{N} = any
  // number, in any script.
  static final RegExp _meaningfulContentRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _wordSplitRegex = RegExp(r'\s+');
  static final RegExp _urlRegex = RegExp(r'^(https?:\/\/[^\s]+)$');

  // Tuning knobs — these are deliberate, not incidental. A CJK/Thai/etc.
  // sentence measures as "1 word" under the space-delimited logic below, so
  // unspaced scripts are judged on character density instead.
  static const _minUnspacedMeaningfulChars = 6;
  static const _minSpaceDelimitedLength = 10;
  static const _minSpaceDelimitedWords = 3;

  // Scripts written without spaces between words (CJK, Thai, Lao, Khmer,
  // Myanmar) \u2014 the whitespace-split word count below is meaningless for
  // these (a full sentence measures as "1 word"), so they need a separate,
  // character-density-based check rather than falling through to the
  // space-delimited-script logic.
  static final RegExp _unspacedScriptRegex = RegExp(
    r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]',
    unicode: true,
  );

  static bool isNoise(String text) {
    final trimmed = text.trim().toLowerCase();
    if (trimmed.isEmpty) return true;

    if (_unspacedScriptRegex.hasMatch(trimmed)) {
      final meaningfulCharCount = _meaningfulContentRegex.allMatches(trimmed).length;
      return meaningfulCharCount < _minUnspacedMeaningfulChars;
    }

    // Space-delimited scripts (Latin, Cyrillic, Arabic, Devanagari, etc.) \u2014
    // behavior unchanged from before the multilingual fix above.
    if (trimmed.length < _minSpaceDelimitedLength ||
        trimmed.split(_wordSplitRegex).length < _minSpaceDelimitedWords) {
      return true;
    }

    if (!_meaningfulContentRegex.hasMatch(trimmed)) {
      return true;
    }

    if (_urlRegex.hasMatch(trimmed)) {
      return true;
    }

    return false;
  }
}

class EmbeddingNoiseFilter {
  static final RegExp _meaningfulContentRegex = RegExp(r'[a-zA-Z0-9\u00C0-\u00FF\u0100-\u017F]');
  static final RegExp _urlRegex = RegExp(r'^(https?:\/\/[^\s]+)$');

  static bool isNoise(String text) {
    final trimmed = text.trim().toLowerCase();

    if (trimmed.length < 10 || trimmed.split(RegExp(r'\s+')).length < 3) {
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

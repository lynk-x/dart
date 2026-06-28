class ImageOptimizer {
  static const String _cdnBase = 'https://cdn.lynk-x.app';

  /// Wraps a CDN URL with Cloudflare Image Resizing parameters.
  static String getOptimizedUrl(
    String url, {
    int? width,
    int? height,
    int quality = 80,
    String fit = 'crop',
  }) {
    if (url.isEmpty) return '';
    if (!url.startsWith(_cdnBase)) {
      return url;
    }

    final relativePath = url.replaceFirst('$_cdnBase/', '');
    final params = <String>[];

    if (width != null) params.add('width=$width');
    if (height != null) params.add('height=$height');
    params.add('quality=$quality');
    params.add('fit=$fit');
    params.add('format=auto');

    final paramString = params.join(',');
    return '$_cdnBase/cdn-cgi/image/$paramString/$relativePath';
  }
}

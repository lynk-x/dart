import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lynk_core/core.dart';
import '../models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';


class ChatLinkPreview extends StatefulWidget {
  final String url;
  final String message;
  final TextStyle textStyle;
  final LinkPreviewData? data;
  final Function(LinkPreviewData)? onFetched;

  const ChatLinkPreview({
    super.key,
    required this.url,
    required this.message,
    required this.textStyle,
    this.data,
    this.onFetched,
  });

  @override
  State<ChatLinkPreview> createState() => _ChatLinkPreviewState();
}

class _ChatLinkPreviewState extends State<ChatLinkPreview> {
  @override
  void initState() {
    super.initState();
    if (widget.data == null) {
      _fetchMetadata();
    }
  }

  Future<void> _fetchMetadata() async {
    try {
      final response = await http.get(
        Uri.parse(widget.url),
        headers: {'User-Agent': 'Mozilla/5.0 (compatible; LynkX/1.0)'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200 || !mounted) return;

      final body = response.body;
      String? og(String prop) {
        final pattern = RegExp(
          '<meta[^>]+property=["\']og:$prop["\'][^>]+content=["\']([^"\']+)["\']',
          caseSensitive: false,
        );
        final m = pattern.firstMatch(body) ??
            RegExp(
              '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:$prop["\']',
              caseSensitive: false,
            ).firstMatch(body);
        return m?.group(1);
      }

      String? meta(String name) {
        final pattern = RegExp(
          '<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']',
          caseSensitive: false,
        );
        final m = pattern.firstMatch(body) ??
            RegExp(
              '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$name["\']',
              caseSensitive: false,
            ).firstMatch(body);
        return m?.group(1);
      }

      String? title() {
        final ogTitle = og('title');
        if (ogTitle != null) return ogTitle;
        final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
            .firstMatch(body);
        return m?.group(1)?.trim();
      }

      final data = LinkPreviewData(
        title: title(),
        description: og('description') ?? meta('description'),
        image: og('image'),
        url: widget.url,
      );

      if (data.title != null || data.image != null) {
        widget.onFetched?.call(data);
      }
    } catch (_) {
      // Network failure or timeout — silently skip preview
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return Text(widget.message, style: widget.textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message, style: widget.textStyle),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.data!.image != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: widget.data!.image!,
                      cacheManager: LynkCacheManager.instance,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 100,
                        width: double.infinity,
                        color: Colors.white12,
                      ),
                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (widget.data!.title != null)
                Text(
                  widget.data!.title!,
                  style: widget.textStyle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.accentColor,
                  ),
                ),
              if (widget.data!.description != null)
                Text(
                  widget.data!.description!,
                  style: widget.textStyle.copyWith(
                      fontSize: 12, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

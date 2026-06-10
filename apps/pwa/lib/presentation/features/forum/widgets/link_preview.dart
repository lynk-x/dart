import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';
import '../models/forum_model.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';


import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final List<TapGestureRecognizer> _gestureRecognizers = [];

  @override
  void initState() {
    super.initState();
    if (widget.data == null) {
      _fetchMetadata();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchMetadata() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'link-preview',
        body: {'url': widget.url},
      );

      if (response.status != 200 || !mounted) return;

      final dataMap = response.data as Map<String, dynamic>?;
      if (dataMap == null) return;

      final data = LinkPreviewData.fromMap(dataMap);

      if (data.title != null || data.image != null) {
        widget.onFetched?.call(data);
      }
    } catch (_) {
      // Network failure or timeout — silently skip preview
    }
  }

  Future<void> _launchUrl() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildRichMessageText() {
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    _gestureRecognizers.clear();

    final urlRegExp = RegExp(r'(?:(?:https?|ftp)://)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    final matches = urlRegExp.allMatches(widget.message);
    if (matches.isEmpty) {
      return Text(widget.message, style: widget.textStyle);
    }

    final List<TextSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: widget.message.substring(lastIndex, match.start),
          style: widget.textStyle,
        ));
      }

      final urlContent = widget.message.substring(match.start, match.end);
      final validUrl = urlContent.startsWith('http') ? urlContent : 'https://$urlContent';

      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(validUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        };
      _gestureRecognizers.add(recognizer);

      spans.add(TextSpan(
        text: urlContent,
        style: widget.textStyle.copyWith(
          color: context.accentColor,
          decoration: TextDecoration.underline,
          decorationColor: context.accentColor,
        ),
        recognizer: recognizer,
      ));
      lastIndex = match.end;
    }

    if (lastIndex < widget.message.length) {
      spans.add(TextSpan(
        text: widget.message.substring(lastIndex),
        style: widget.textStyle,
      ));
    }

    final textWidget = Text.rich(TextSpan(children: spans));
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
      return SelectionArea(child: textWidget);
    }
    return textWidget;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return _buildRichMessageText();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRichMessageText(),
        const SizedBox(height: 4),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _launchUrl,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                        decoration: TextDecoration.underline,
                        decorationColor: context.accentColor,
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
          ),
        ),
      ],
    );
  }
}

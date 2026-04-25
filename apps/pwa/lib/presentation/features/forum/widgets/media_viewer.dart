import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'interstitial_ad.dart';

/// A full-screen multimedia viewer for high-resolution images.
///
/// Includes common interactive features like downloading and sharing/replying
/// to media content.
class MediaViewer extends StatelessWidget {
  /// The URL of the image to display (from chat).
  final String? imageUrl;

  /// The full media object to display (from media tab).
  final ForumMedia? mediaItem;

  /// Callback triggered when the 'Mention' action is selected.
  final VoidCallback? onMention;

  /// Callback triggered when the 'Approve' action is selected (organizers only).
  final VoidCallback? onApprove;

  /// The pre-fetched interstitial ad to display on download.
  final AdModel? interstitialAd;

  const MediaViewer({
    super.key,
    this.imageUrl,
    this.mediaItem,
    this.onMention,
    this.onApprove,
    this.interstitialAd,
  });

  /// Helper method to show the viewer in a full-screen dialog.
  static void show(BuildContext context,
      {String? imageUrl,
      ForumMedia? mediaItem,
      VoidCallback? onMention,
      VoidCallback? onApprove,
      AdModel? interstitialAd}) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: MediaViewer(
            imageUrl: imageUrl,
            mediaItem: mediaItem,
            onMention: onMention,
            onApprove: onApprove,
            interstitialAd: interstitialAd),
      ),
    );
  }

  Future<void> _downloadMedia(BuildContext context) async {
    final targetUrl = mediaItem?.url ?? imageUrl;
    if (targetUrl == null) return;

    if (kIsWeb) {
      final uri = Uri.tryParse(targetUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    try {
      final hasAccess = await Gal.requestAccess();
      if (!hasAccess) return;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading media...')),
        );
      }

      final tempDir = await getTemporaryDirectory();
      final isVideo =
          mediaItem?.mediaType == 'video' || targetUrl.contains('.mp4');
      final ext = isVideo ? 'mp4' : 'jpg';
      final savePath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Dio().download(targetUrl, savePath);

      if (isVideo) {
        await Gal.putVideo(savePath);
      } else {
        await Gal.putImage(savePath);
      }

      if (context.mounted) {
        if (interstitialAd != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (adContext) => InterstitialAd(
                ad: interstitialAd!,
                onClose: () {
                  Navigator.pop(adContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Media saved to gallery!')),
                  );
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Media saved to gallery!')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download media.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.grey[900],
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image, color: Colors.white24, size: 100),
                  SizedBox(height: 16),
                  Text('High-Res Media Preview',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGalleryAction(
                Icons.download,
                'Save',
                onTap: () => _downloadMedia(context),
              ),
              _buildGalleryAction(
                Icons.alternate_email,
                'Mention',
                onTap: () {
                  Navigator.pop(context);
                  onMention?.call();
                },
              ),
              if (onApprove != null)
                _buildGalleryAction(
                  Icons.check_circle_outline,
                  'Approve',
                  onTap: () {
                    Navigator.pop(context);
                    onApprove?.call();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Media approved!')),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryAction(IconData icon, String label,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

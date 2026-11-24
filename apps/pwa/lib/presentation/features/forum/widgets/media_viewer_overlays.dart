import 'package:material_ui/material_ui.dart';
import 'package:lynk_x/core/utils/time_ago.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_core/core.dart';

/// "Shared by [name] · [relative time]" caption shown below the media, in
/// the viewer's own column (not overlaid on the image). Omits the "Shared
/// by" clause entirely (rather than showing a blank name) when uploaderName
/// isn't available — e.g. a realtime-inserted item whose flat payload has no
/// joined profile until the next refreshMedia() fetch.
class MediaAttribution extends StatelessWidget {
  final ForumMedia media;
  final bool isUploader;

  const MediaAttribution(
      {super.key, required this.media, required this.isUploader});

  @override
  Widget build(BuildContext context) {
    final relativeTime = formatTimeAgo(media.createdAt);
    final uploaderName = media.uploaderName;
    final displayName = isUploader ? 'You' : uploaderName;
    final text = displayName != null && displayName.isNotEmpty
        ? 'Shared by $displayName · $relativeTime'
        : relativeTime;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          text,
          style: AppTypography.inter(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        if (!media.hasDistributionRights) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.privacy_tip,
                size: 11,
                color: Colors.amberAccent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
              Text(
                'Restricted distribution rights',
                style: AppTypography.inter(
                  fontSize: 10,
                  color: Colors.amberAccent.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shared confirm-before-delete dialog for any "this permanently removes
/// media" action in the viewer — the uploader's own-upload delete and a
/// moderator deleting already-approved media both go through this, so a
/// destructive tap is never a single accidental press.
void showMediaDeleteConfirmation(BuildContext context, VoidCallback onDelete) {
  showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete this upload?',
          style: TextStyle(color: Colors.white)),
      content: const Text(
        'This will be removed for everyone.',
        style: TextStyle(color: Colors.white54),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  ).then((confirmed) {
    if (confirmed == true) onDelete();
  });
}

/// Non-authorized members' single action next to the attribution chip:
/// Delete for their own upload, Report for anyone else's. Organizers/
/// moderators never see this — they use the bottom Approve/Reject bar
/// instead, so the same person never gets two different ways to remove
/// the same item.
class MediaMemberAction extends StatelessWidget {
  final ForumMedia media;
  final bool isUploader;
  final bool isAuthorized;
  final VoidCallback onDelete;
  final VoidCallback onRevokeDistributionRights;
  final ValueChanged<bool> onToggleDistributionRights;
  final ValueChanged<String> onReport;

  const MediaMemberAction({
    super.key,
    required this.media,
    required this.isUploader,
    this.isAuthorized = false,
    required this.onDelete,
    required this.onRevokeDistributionRights,
    required this.onToggleDistributionRights,
    required this.onReport,
  });

  void _confirmDelete(BuildContext context) {
    showMediaDeleteConfirmation(context, onDelete);
  }

  void _showReportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report this media',
                style: AppTypography.interTight(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              // (reason_id, label) pairs — reason_id must match a row in
              // reports.report_reasons; a mismatched id fails the report's
              // foreign key at insert time.
              ...const [
                ('spam', 'Spam', null),
                ('harassment', 'Harassment', null),
                ('inappropriate', 'Inappropriate Content', null),
                (
                  'likeness_no_consent',
                  "I'm in this without my consent",
                  'Hides immediately pending review'
                ),
              ].map((entry) {
                final (reasonId, label, subtitle) = entry;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(label, style: const TextStyle(color: Colors.white)),
                  subtitle: subtitle != null
                      ? Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12))
                      : null,
                  onTap: () {
                    onReport(reasonId);
                    Navigator.pop(bottomSheetContext);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Media Options',
                style: AppTypography.interTight(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (isUploader || isAuthorized) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text(
                    'Distribution rights',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                  subtitle: Text(
                    media.hasDistributionRights
                        ? 'Public distribution is enabled for this photo/video.'
                        : 'Public distribution is disabled for this photo/video.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: media.hasDistributionRights,
                    activeThumbColor: context.accentColor,
                    onChanged: (val) {
                      Navigator.pop(bottomSheetContext);
                      onToggleDistributionRights(val);
                    },
                  ),
                ),
                if (isUploader || isAuthorized) ...[
                  const Divider(color: Colors.white12, height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                    ),
                    title: Text(
                      media.mediaType == 'video'
                          ? 'Delete Video'
                          : 'Delete Photo',
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                    ),
                    subtitle: const Text(
                      'Permanently remove this upload from the forum',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(bottomSheetContext);
                      _confirmDelete(context);
                    },
                  ),
                ],
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: media.hasDistributionRights
                          ? Colors.amberAccent.withValues(alpha: 0.12)
                          : Colors.greenAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.privacy_tip,
                      color: media.hasDistributionRights
                          ? Colors.amberAccent
                          : Colors.greenAccent,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    media.hasDistributionRights
                        ? 'Revoke distribution rights'
                        : 'Distribution rights revoked',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                  subtitle: Text(
                    media.hasDistributionRights
                        ? 'The photo/video stays in the forum, but public distribution is disabled.'
                        : 'This photo/video stays in the forum. Public distribution is disabled.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: media.hasDistributionRights
                      ? const Icon(Icons.chevron_right,
                          color: Colors.white38, size: 20)
                      : const Icon(Icons.check_circle,
                          color: Colors.greenAccent, size: 20),
                  onTap: media.hasDistributionRights
                      ? () {
                          Navigator.pop(bottomSheetContext);
                          onRevokeDistributionRights();
                        }
                      : null,
                ),
                const Divider(color: Colors.white12, height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag_outlined,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text(
                    'Report Content Violation',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Inappropriate content, spam, or harassment',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white38, size: 20),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _showReportSheet(context);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showOptionsSheet(context),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert,
          size: 16,
          color: Colors.white70,
        ),
      ),
    );
  }
}

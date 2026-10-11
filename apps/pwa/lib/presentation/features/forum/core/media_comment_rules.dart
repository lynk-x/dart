/// Whether the media viewer's quick comment box may show for the photo or video on screen.
///
/// The box follows the chat composer's rules: nobody who is signed out, no one in an archived or read-only forum
/// (organizers excepted, as in the composer), and no muted member. It also needs a real, approved item: a
/// still-pending upload is not visible to the forum yet, and a standalone image (opened by URL, with no media row)
/// has nothing to attach to.
bool canCommentOnMedia({
  required bool chatEnabled,
  required String? mediaId,
  required bool mediaApproved,
  required String? userId,
  required bool isGuest,
  required bool isOrganizer,
  required bool forumReadOnly,
  required bool forumArchived,
  required bool isMuted,
}) {
  if (!chatEnabled || mediaId == null || mediaId == 'standalone' || !mediaApproved) return false;
  if (userId == null || isGuest) return false;
  if (isMuted) return false;
  if ((forumArchived || forumReadOnly) && !isOrganizer) return false;
  return true;
}

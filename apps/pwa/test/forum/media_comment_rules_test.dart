import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/forum/core/media_comment_rules.dart';

bool _can({
  bool chatEnabled = true,
  String? mediaId = 'm1',
  bool mediaApproved = true,
  String? userId = 'u1',
  bool isGuest = false,
  bool isOrganizer = false,
  bool forumReadOnly = false,
  bool forumArchived = false,
  bool isMuted = false,
}) =>
    canCommentOnMedia(
      chatEnabled: chatEnabled,
      mediaId: mediaId,
      mediaApproved: mediaApproved,
      userId: userId,
      isGuest: isGuest,
      isOrganizer: isOrganizer,
      forumReadOnly: forumReadOnly,
      forumArchived: forumArchived,
      isMuted: isMuted,
    );

void main() {
  group('canCommentOnMedia', () {
    test('an ordinary member can comment on approved media', () => expect(_can(), isTrue));

    test('chat switched off hides it', () => expect(_can(chatEnabled: false), isFalse));

    test('pending media hides it for everyone, organizers included', () {
      expect(_can(mediaApproved: false), isFalse);
      expect(_can(mediaApproved: false, isOrganizer: true), isFalse);
    });

    test('standalone images and missing media have nothing to attach to', () {
      expect(_can(mediaId: 'standalone'), isFalse);
      expect(_can(mediaId: null), isFalse);
    });

    test('signed-out and guest users cannot comment', () {
      expect(_can(userId: null), isFalse);
      expect(_can(isGuest: true), isFalse);
    });

    test('a muted member cannot comment, organizers included', () {
      expect(_can(isMuted: true), isFalse);
      expect(_can(isMuted: true, isOrganizer: true), isFalse);
    });

    test('read-only and archived forums block members but not the organizer', () {
      expect(_can(forumReadOnly: true), isFalse);
      expect(_can(forumArchived: true), isFalse);
      expect(_can(forumReadOnly: true, isOrganizer: true), isTrue);
      expect(_can(forumArchived: true, isOrganizer: true), isTrue);
    });
  });
}

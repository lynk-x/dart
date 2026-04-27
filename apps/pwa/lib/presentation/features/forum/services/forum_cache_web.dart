import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumCache {
  static Future<void> cacheMemberInfo({
    required String forumId,
    required String userId,
    required String role,
    required Map<String, dynamic> capabilities,
  }) async {}

  static Future<Map<String, dynamic>?> getCachedMemberInfo(
    String forumId,
    String userId,
  ) async => null;

  static Future<void> cacheMessages(
    List<ChatMessage> messages,
    String forumId,
  ) async {}

  static Future<List<ChatMessage>> getCachedMessages(
    String forumId,
    String currentUserId, {
    String? type,
  }) async => [];

  static Future<void> clearCache(String forumId) async {}
}

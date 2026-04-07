import 'package:flutter/material.dart';

/// A reusable bar for selecting reaction emojis.
///
/// This widget displays a horizontal list of emojis that players can tap
/// to trigger live reactions in the forum.
class ReactionBar extends StatelessWidget {
  /// Callback triggered when an emoji is tapped.
  final Function(String) onEmojiTap;

  /// The list of emojis to display in the bar.
  final List<String> emojis;

  const ReactionBar({
    super.key,
    required this.onEmojiTap,
    this.emojis = const ['❤️', '🔥', '😂', '🎉', '👍', '👎', '🥁', '❌'],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: emojis.map((emoji) => _buildReactionEmoji(emoji)).toList(),
    );
  }

  Widget _buildReactionEmoji(String emoji) {
    return GestureDetector(
      onTap: () => onEmojiTap(emoji),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}

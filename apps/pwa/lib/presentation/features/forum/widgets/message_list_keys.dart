import 'package:flutter/widgets.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

// Helpers for the forum's reversed chat lists (Updates and Live Chat).
//
// Both lists are `reverse: true` with the newest message at index 0, so every incoming message
// shifts all existing items one index. Flutter reconciles list children by key when it can find
// them, otherwise by position — and by position, the child now at index i is a different message
// than before, so every visible bubble is torn down and rebuilt from scratch (losing link
// previews, loaded images, selection and animation state) each time anyone sends anything.
// Two things make Flutter move the existing elements instead:
//   1. the OUTERMOST widget an item builder returns must carry the key ([keyedMessageItem]) — a
//      key on a nested widget is invisible to the list;
//   2. the delegate needs [messageChildIndexFinder] to look up a key's new index.

/// Wraps [child] in the message's key. Use it on whatever the item builder returns.
Widget keyedMessageItem(ChatMessage message, Widget child) =>
    KeyedSubtree(key: ValueKey<String>(message.id), child: child);

/// For `SliverChildBuilderDelegate.findChildIndexCallback`: maps a [keyedMessageItem] key to the
/// message's current index. The id→index table is built once, on the first lookup of a rebuild.
int? Function(Key) messageChildIndexFinder(List<ChatMessage> messages) {
  Map<String, int>? indexById;
  return (Key key) {
    if (key is! ValueKey<String>) return null;
    indexById ??= {
      for (var i = 0; i < messages.length; i++) messages[i].id: i,
    };
    return indexById![key.value];
  };
}

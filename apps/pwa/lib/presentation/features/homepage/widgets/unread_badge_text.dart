/// Text for a forum's unread badge on the home list: the real count, capped at "99+" so a long
/// absence doesn't produce a badge wider than the card. Callers hide the badge for 0.
String unreadBadgeText(int unreadCount) => unreadCount > 99 ? '99+' : '$unreadCount';

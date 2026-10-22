/// Role of the active user in the forum's audio/video room session.
///
/// Lives in its own file (not inside [ForumHeader]) so [ForumVideoStreamService]
/// and other services can depend on it without importing a widget — a service
/// importing `widgets/header.dart` would be a layering inversion.
enum ForumHeaderRole { host, speaker, listener }
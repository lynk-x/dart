/// A notification category the user can set delivery preferences for —
/// sourced from `api.v1_notification_types`, which already excludes
/// always-on security categories (auth, account_security) server-side.
class NotificationCategory {
  final String id;
  final String displayName;
  final String? description;
  /// Server-side fallback `comms.fn_notify_user` actually honors when the
  /// user has no `notification_preferences` row for this category yet —
  /// not just a UI hint, so a category shown as "on" here matches what the
  /// backend will really send before the user touches this screen.
  final bool defaultEmail;

  const NotificationCategory({
    required this.id,
    required this.displayName,
    this.description,
    this.defaultEmail = false,
  });

  factory NotificationCategory.fromMap(Map<String, dynamic> map) {
    return NotificationCategory(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      description: map['description'] as String?,
      defaultEmail: map['default_email'] as bool? ?? false,
    );
  }
}

/// Per-category delivery-channel preference. A category with no row yet in
/// `comms.notification_preferences` has never been explicitly set by the
/// user — [inApp]/[push] default to true, matching the column defaults on
/// the underlying table. [email]'s constructor default of false is only a
/// fallback for when a [NotificationCategory] isn't available to consult —
/// callers merging against a category should pass
/// `email: category.defaultEmail` (see [NotificationPreferencesCubit.load])
/// so an unset category matches what the backend will actually send.
class NotificationPreference {
  final String type;
  final bool inApp;
  final bool push;
  final bool email;

  const NotificationPreference({
    required this.type,
    this.inApp = true,
    this.push = true,
    this.email = false,
  });

  factory NotificationPreference.fromMap(Map<String, dynamic> map) {
    return NotificationPreference(
      type: map['type'] as String,
      inApp: map['in_app'] as bool? ?? true,
      push: map['push'] as bool? ?? true,
      email: map['email'] as bool? ?? false,
    );
  }

  NotificationPreference copyWith({bool? inApp, bool? push, bool? email}) {
    return NotificationPreference(
      type: type,
      inApp: inApp ?? this.inApp,
      push: push ?? this.push,
      email: email ?? this.email,
    );
  }
}

import '../domain/models/notification_preference_model.dart';

class NotificationPreferenceItem {
  final NotificationCategory category;
  final NotificationPreference preference;

  const NotificationPreferenceItem({
    required this.category,
    required this.preference,
  });
}

abstract class NotificationPreferencesState {
  const NotificationPreferencesState();
}

class NotificationPreferencesInitial extends NotificationPreferencesState {
  const NotificationPreferencesInitial();
}

class NotificationPreferencesLoading extends NotificationPreferencesState {
  const NotificationPreferencesLoading();
}

class NotificationPreferencesLoaded extends NotificationPreferencesState {
  final List<NotificationPreferenceItem> items;
  /// Type currently being saved, if any — used to show a per-row spinner
  /// instead of blocking the whole screen on one toggle's round trip.
  final String? savingType;
  final String? error;

  const NotificationPreferencesLoaded({
    required this.items,
    this.savingType,
    this.error,
  });

  NotificationPreferencesLoaded copyWith({
    List<NotificationPreferenceItem>? items,
    String? savingType,
    bool clearSavingType = false,
    String? error,
    bool clearError = false,
  }) {
    return NotificationPreferencesLoaded(
      items: items ?? this.items,
      savingType: clearSavingType ? null : (savingType ?? this.savingType),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationPreferencesError extends NotificationPreferencesState {
  final String message;
  const NotificationPreferencesError(this.message);
}

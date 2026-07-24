import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:lynk_core/core.dart';
import '../data/repositories/notification_preferences_repository.dart';

class NotificationPreferencesCubit extends Cubit<NotificationPreferencesState> {
  final NotificationPreferencesRepository _repo;
  NotificationPreferencesCubit(this._repo) : super(const NotificationPreferencesInitial());

  Future<void> load() async {
    emit(const NotificationPreferencesLoading());
    try {
      final results = await Future.wait([
        _repo.getCategories(),
        _repo.getPreferences(),
      ]);
      final categories = results[0] as List<NotificationCategory>;
      final preferences = results[1] as List<NotificationPreference>;
      final byType = {for (final p in preferences) p.type: p};

      final items = categories
          .map((c) => NotificationPreferenceItem(
                category: c,
                preference: byType[c.id] ??
                    NotificationPreference(type: c.id, email: c.defaultEmail),
              ))
          .toList();

      emit(NotificationPreferencesLoaded(items: items));
    } catch (e) {
      emit(NotificationPreferencesError(e.toFriendlyMessage()));
    }
  }

  /// Updates one category's preference optimistically, then confirms with
  /// the server; reverts that single row (not the whole list) on failure so
  /// one bad toggle doesn't discard other unsaved-looking state.
  Future<void> updatePreference(
    String type, {
    bool? inApp,
    bool? push,
    bool? email,
  }) async {
    final currentState = state;
    if (currentState is! NotificationPreferencesLoaded) return;

    final index = currentState.items.indexWhere((i) => i.category.id == type);
    if (index == -1) return;

    final previous = currentState.items[index];
    final updatedPreference = previous.preference.copyWith(
      inApp: inApp,
      push: push,
      email: email,
    );
    final optimisticItems = List<NotificationPreferenceItem>.from(currentState.items);
    optimisticItems[index] = NotificationPreferenceItem(
      category: previous.category,
      preference: updatedPreference,
    );

    emit(currentState.copyWith(
      items: optimisticItems,
      savingType: type,
      clearError: true,
    ));

    try {
      await _repo.upsertPreference(
        type: type,
        inApp: updatedPreference.inApp,
        push: updatedPreference.push,
        email: updatedPreference.email,
      );
      final next = state;
      if (next is! NotificationPreferencesLoaded) return;
      emit(next.copyWith(clearSavingType: true));
    } catch (e) {
      debugPrint('[NotificationPreferencesCubit] updatePreference failed: $e');
      final next = state;
      if (next is! NotificationPreferencesLoaded) return;
      final revertedItems = List<NotificationPreferenceItem>.from(next.items);
      final revertIndex = revertedItems.indexWhere((i) => i.category.id == type);
      if (revertIndex != -1) revertedItems[revertIndex] = previous;
      emit(next.copyWith(
        items: revertedItems,
        clearSavingType: true,
        error: e.toFriendlyMessage(),
      ));
    }
  }
}

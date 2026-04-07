import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumMediaState extends Equatable {
  final List<ForumMedia> mediaItems;
  final bool isLoading;
  final bool isUploading;
  final String? error;

  const ForumMediaState({
    this.mediaItems = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.error,
  });

  ForumMediaState copyWith({
    List<ForumMedia>? mediaItems,
    bool? isLoading,
    bool? isUploading,
    String? error,
    bool clearError = false,
  }) {
    return ForumMediaState(
      mediaItems: mediaItems ?? this.mediaItems,
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [mediaItems, isLoading, isUploading, error];
}

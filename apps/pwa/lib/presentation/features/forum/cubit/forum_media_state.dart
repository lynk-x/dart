import 'package:equatable/equatable.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumMediaState extends Equatable {
  final List<ForumMedia> mediaItems;
  final bool isLoading;
  final bool isUploading;
  final bool hasMore;
  final int uploadCurrent;
  final int uploadTotal;
  // 0.0-1.0 progress of the file currently uploading.
  final double uploadProgress;
  final String? error;

  const ForumMediaState({
    this.mediaItems = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.hasMore = true,
    this.uploadCurrent = 0,
    this.uploadTotal = 0,
    this.uploadProgress = 0.0,
    this.error,
  });

  ForumMediaState copyWith({
    List<ForumMedia>? mediaItems,
    bool? isLoading,
    bool? isUploading,
    bool? hasMore,
    int? uploadCurrent,
    int? uploadTotal,
    double? uploadProgress,
    String? error,
    bool clearError = false,
  }) {
    return ForumMediaState(
      mediaItems: mediaItems ?? this.mediaItems,
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      hasMore: hasMore ?? this.hasMore,
      uploadCurrent: uploadCurrent ?? this.uploadCurrent,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        mediaItems,
        isLoading,
        isUploading,
        hasMore,
        uploadCurrent,
        uploadTotal,
        uploadProgress,
        error,
      ];

  /// Presigned Cloudflare R2 storage URLs expire after 1 hour (X-Amz-Expires=3600).
  /// Persisting them to disk cache causes HTTP 403 Forbidden errors when reopening
  /// the app later. Fresh signed URLs are loaded on startup via [ForumMediaCubit.refreshMedia].
  Map<String, dynamic> toJson() => {};

  static ForumMediaState fromMap(Map<String, dynamic> map) =>
      const ForumMediaState();
}

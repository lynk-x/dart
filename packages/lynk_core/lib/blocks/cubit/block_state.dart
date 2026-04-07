part of 'block_cubit.dart';

class BlockState extends Equatable {
  final Set<String> blockedIds;
  final bool isLoading;
  final String? error;

  const BlockState({
    this.blockedIds = const {},
    this.isLoading = false,
    this.error,
  });

  BlockState copyWith({
    Set<String>? blockedIds,
    bool? isLoading,
    String? error,
  }) {
    return BlockState(
      blockedIds: blockedIds ?? this.blockedIds,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [blockedIds, isLoading, error];
}

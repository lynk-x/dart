import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:equatable/equatable.dart';

part 'block_state.dart';

class BlockCubit extends Cubit<BlockState> {
  BlockCubit() : super(const BlockState());

  Future<void> init() async {
    await fetchBlocks();
  }

  Future<void> fetchBlocks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    emit(state.copyWith(isLoading: true));
    try {
      final data = await Supabase.instance.client
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', userId);

      final blockedIds =
          (data as List).map((item) => item['blocked_id'] as String).toSet();
      emit(state.copyWith(blockedIds: blockedIds, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> blockUser(String targetUserId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('user_blocks').insert({
        'blocker_id': userId,
        'blocked_id': targetUserId,
      });

      final updatedIds = Set<String>.from(state.blockedIds)..add(targetUserId);
      emit(state.copyWith(blockedIds: updatedIds));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('user_blocks')
          .delete()
          .eq('blocker_id', userId)
          .eq('blocked_id', targetUserId);

      final updatedIds = Set<String>.from(state.blockedIds)
        ..remove(targetUserId);
      emit(state.copyWith(blockedIds: updatedIds));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  bool isBlocked(String targetUserId) {
    return state.blockedIds.contains(targetUserId);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import '../cubit/forum_cubit.dart';
import '../cubit/forum_state.dart';
import '../cubit/forum_chat_cubit.dart';
import '../cubit/forum_updates_cubit.dart';

/// Navigation Tab Bar for switching between Updates, Live Chat, and Media tabs in the Forum.
class ForumTabBar extends StatelessWidget {
  final Function(int) onTabSelected;

  const ForumTabBar({
    super.key,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeatureFlagCubit, FeatureFlagState>(
      builder: (context, _) {
        final featureFlags = context.read<FeatureFlagCubit>();
        final showUpdates =
            featureFlags.isEnabled('enable_forum_announcements');
        final showChat = featureFlags.isEnabled('enable_forum_live_chat');
        final showMedia = featureFlags.isEnabled('enable_forum_media');

        return BlocBuilder<ForumCubit, ForumState>(
          buildWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
          builder: (context, state) {
            final updatesSearchQuery =
                context.select((ForumUpdatesCubit c) => c.state.searchQuery);
            final updatesCount = context
                .select((ForumUpdatesCubit c) => c.state.messages.length);
            final chatSearchQuery =
                context.select((ForumChatCubit c) => c.state.searchQuery);
            final chatCount =
                context.select((ForumChatCubit c) => c.state.messages.length);

            final updatesDisplayCount =
                updatesSearchQuery.isNotEmpty ? updatesCount : null;
            final chatDisplayCount =
                chatSearchQuery.isNotEmpty ? chatCount : null;

            int displayedIndex = 0;
            return Container(
              height: 48,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (showUpdates)
                    _buildTab(
                      context,
                      'Updates',
                      displayedIndex++,
                      state.currentTabIndex,
                      count: updatesDisplayCount,
                    ),
                  if (showChat)
                    _buildTab(
                      context,
                      'Live chat',
                      displayedIndex++,
                      state.currentTabIndex,
                      hasIndicator: true,
                      count: chatDisplayCount,
                    ),
                  if (showMedia)
                    _buildTab(
                      context,
                      'Media',
                      displayedIndex++,
                      state.currentTabIndex,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTab(
    BuildContext context,
    String label,
    int index,
    int currentIndex, {
    bool hasIndicator = false,
    int? count,
  }) {
    bool isActive = currentIndex == index;
    bool showIndicator = hasIndicator && !isActive;
    final displayLabel = count != null ? '$label ($count)' : label;

    return GestureDetector(
      onTap: () => onTabSelected(index),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIndicator)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  displayLabel,
                  style: AppTypography.inter(
                    fontSize: 16,
                    color: isActive ? Colors.white : Colors.white38,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 3,
              width: 40,
              decoration: BoxDecoration(
                color: isActive ? context.accentColor : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

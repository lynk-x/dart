import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/features/forum/widgets/info_banner.dart';
import 'package:lynk_x/presentation/features/forum/widgets/category_filter_bar.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/reaction_bar.dart';

/// The tab-specific strip under the forum tab bar and the height it takes: category filter and
/// pinned-message banner on Updates, the emoji reaction bar on Live Chat, nothing elsewhere.
/// The caller adds the height to the pinned header so the sliver is sized to fit.
({double height, Widget? widget}) buildForumHeaderExtras(
  BuildContext context, {
  required ForumState forumState,
  required bool showUpdates,
}) {
  double extraHeight = 0;
  Widget? extraHeaderWidgets;

  final featureFlags =
      context.read<FeatureFlagCubit>();
  final showChat = featureFlags
      .isEnabled('enable_forum_live_chat');
  final chatTabIndex = showUpdates ? 1 : 0;

  if (forumState.currentTabIndex == 0 &&
      showUpdates) {
    final updatesCubit =
        context.read<ForumUpdatesCubit>();
    final selectedCategory = context
        .select<ForumUpdatesCubit, String?>(
      (c) => c.state.selectedCategory,
    );
    final pinnedMessage = context.select<
        ForumUpdatesCubit, ChatMessage?>(
      (c) {
        for (final m in c.state.messages) {
          if (m.isPinned) return m;
        }
        return null;
      },
    );

    extraHeight += 52.0; // CategoryFilterBar
    if (pinnedMessage != null) {
      extraHeight +=
          48.0; // InfoBanner exact calculated height for 2 lines
    }

    extraHeaderWidgets = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: AppColors.primaryBackground,
          child: CategoryFilterBar(
            selectedCategory:
                selectedCategory,
            onSelectionChanged: (cat) =>
                updatesCubit.setCategory(cat),
          ),
        ),
        if (pinnedMessage != null)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
                    4, 4, 4, 4),
            child: InfoBanner(
              icon: Icons.push_pin,
              text: pinnedMessage
                          .message.length >
                      80
                  ? '${pinnedMessage.message.substring(0, 80)}…'
                  : pinnedMessage.message,
            ),
          ),
      ],
    );
  } else if (forumState.currentTabIndex ==
          chatTabIndex &&
      showChat) {
    extraHeight +=
        44.0; // ReactionBar height + vertical padding
    extraHeaderWidgets = ColoredBox(
      color: AppColors.primaryBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 8.0),
        child: ReactionBar(
          onEmojiTap: (emoji) => context
              .read<ForumCubit>()
              .handleEmojiTap(emoji),
        ),
      ),
    );
  }

  return (height: extraHeight, widget: extraHeaderWidgets);
}

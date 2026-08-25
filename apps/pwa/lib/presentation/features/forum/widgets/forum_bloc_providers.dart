import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_ads_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_presence_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_media_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_cubit.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_audio_stream_service.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';

/// Clean wrapper that manages feature-level BLoC tree instantiation for ForumView
class ForumBlocProviders extends StatelessWidget {
  final String forumId;
  final ForumCubit mainCubit;
  final ForumState state;
  final Widget child;

  const ForumBlocProviders({
    super.key,
    required this.forumId,
    required this.mainCubit,
    required this.state,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      key: const ValueKey('content'),
      providers: [
        BlocProvider(
          create: (context) {
            final ads = ForumAdsCubit(
              forumId: forumId,
              userId: mainCubit.userId,
              isPremium: !state.showAds,
              eventId: state.eventId,
              eventCreatedAt: state.eventCreatedAt,
            );
            if (context.read<FeatureFlagCubit>().isEnabled('enable_forum_ads')) {
              ads.init();
            }
            return ads;
          },
        ),
        BlocProvider(
          create: (context) {
            final cubit = ForumPresenceCubit(
              forumId: forumId,
              userId: mainCubit.userId,
              userName: mainCubit.userName,
              isOrganizer: state.isOrganizer,
              isPremium: state.isPremium,
            );
            final flagEnabled = context
                .read<FeatureFlagCubit>()
                .isEnabled('enable_realtime_presence');
            if (flagEnabled) {
              cubit.init();
            }
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            final cubit = ForumUpdatesCubit(
              forumId: forumId,
              userId: mainCubit.userId,
              userName: mainCubit.userName,
              repo: forumRepository,
            )..init();
            cubit.syncForumContext(
              forumCreatedAt: state.forumCreatedAt,
              channelId: state.channelId,
              channelCreatedAt: state.channelCreatedAt,
            );
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            final cubit = ForumChatCubit(
              forumId: forumId,
              userId: mainCubit.userId,
              userName: mainCubit.userName,
              repo: forumRepository,
            )..init();
            cubit.syncForumContext(
              forumCreatedAt: state.forumCreatedAt,
              channelId: state.channelId,
              channelCreatedAt: state.channelCreatedAt,
            );
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) => ForumMediaCubit(
            forumId: forumId,
            userId: mainCubit.userId,
            isOrganizer: state.isOrganizer,
            isModerator: state.isModerator,
            repo: forumRepository,
          )..init(),
        ),
        BlocProvider(
          create: (context) => ForumAudioStreamCubit(
            service: ForumAudioStreamService(supabase: Supabase.instance.client),
            forumId: forumId,
            userId: mainCubit.userId,
            userName: mainCubit.userName,
            isOrganizer: state.isOrganizer,
          )..initRealtimeSubscription(),
        ),
      ],
      child: child,
    );
  }
}

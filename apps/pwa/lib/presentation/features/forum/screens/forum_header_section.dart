import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/widgets/header.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_state.dart';
import 'package:lynk_x/presentation/features/forum/services/forum_audio_stream_service.dart'
    show AudioCallTelemetry;
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'forum_call_actions.dart';

/// The forum header (call/stream controls, search, lock) wired to the audio-call state and the
/// live-stream service. Its own widget so ForumView.build isn't buried under this wiring; it
/// rebuilds on audio-call changes and whenever the screen does (e.g. after a mic toggle).
class ForumHeaderSection extends StatelessWidget {
  final ForumState forumState;

  /// True while a live video stream is running.
  final bool isLive;

  /// Start-call/stream gestures only exist on the Updates tab.
  final bool isUpdatesTabActive;

  /// Repaints the screen after a change to the (non-observable) video service.
  final VoidCallback onVideoStateChanged;

  const ForumHeaderSection({
    super.key,
    required this.forumState,
    required this.isLive,
    required this.isUpdatesTabActive,
    required this.onVideoStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ForumCubit>();
    return BlocBuilder<ForumAudioStreamCubit, ForumAudioStreamState>(
      builder: (context, audioState) {
        final audioCubit = context.read<ForumAudioStreamCubit>();
        final videoService = ForumVideoStreamService();
        return ValueListenableBuilder<AudioCallTelemetry>(
          valueListenable: audioCubit.service.listenerTelemetryNotifier,
          builder: (context, audioTelemetry, _) {
            return ForumHeader(
                                                                        isVideoStreamLive:
                                                                            isLive,
                                                                        isAudioLive:
                                                                            audioState.isLive,
                                                                        isWeakConnection: !isLive &&
                                                                            audioState.isLive &&
                                                                            audioState.role !=
                                                                                ForumHeaderRole
                                                                                    .host &&
                                                                            audioTelemetry
                                                                                .isPoorConnection,
                                                                        isReconnecting: !isLive &&
                                                                            audioState.isLive &&
                                                                            (audioState
                                                                                    .isReconnecting ||
                                                                                audioState
                                                                                    .isListenerReconnecting),
                                                                        role: isLive &&
                                                                                forumState
                                                                                    .isOrganizer
                                                                            ? ForumHeaderRole
                                                                                .host
                                                                            : audioState.role,
                                                                        activeSpeakerNames:
                                                                            audioState
                                                                                .activeSpeakerNames,
                                                                        currentUserName: cubit
                                                                            .state.userName,
                                                                        isMicMuted: isLive
                                                                            ? videoService
                                                                                .isMicMuted
                                                                            : audioState
                                                                                .isMicMuted,
                                                                        isCameraOn: videoService
                                                                            .isCameraOn,
                                                                        isBroadcastMuted:
                                                                            audioState
                                                                                .isBroadcastMuted,
                                                                        getAudioLevel: () => isLive
                                                                            ? videoService
                                                                                .getAudioLevel()
                                                                            : audioCubit.service
                                                                                .getAudioLevel(),
                onToggleMic: () => toggleForumMic(
                  context,
                  isLive: isLive,
                  audioState: audioState,
                  audioCubit: audioCubit,
                  onVideoStateChanged: onVideoStateChanged,
                ),
                onToggleCamera: () => toggleForumCamera(
                  isLive: isLive,
                  onVideoStateChanged: onVideoStateChanged,
                ),
                                                                        onToggleBroadcastMute:
                                                                            () => audioCubit
                                                                                .toggleBroadcastMute(),
                onEndBroadcast: () => endForumBroadcast(
                  context,
                  forumState: forumState,
                  isLive: isLive,
                  audioCubit: audioCubit,
                ),
                                                                        // Header start gestures
                                                                        // are test-only "cheat
                                                                        // codes" for now, but
                                                                        // are still restricted to
                                                                        // the Updates tab for
                                                                        // consistency with where
                                                                        // call/stream/quiz
                                                                        // creation now lives.
                onStartLiveStream: !isUpdatesTabActive
                    ? null
                    : () => startForumLiveStream(context, forumState: forumState),
                onStartAudioStream: !isUpdatesTabActive
                    ? null
                    : () => startForumAudioStream(
                        context,
                        forumState: forumState,
                        audioCubit: audioCubit,
                      ),
                                                                        isOrganizer: forumState
                                                                            .isOrganizer,
                                                                        isReadOnly: forumState
                                                                            .isReadOnly,
                                                                        forumName: forumState
                                                                            .forumName,
                                                                        onLockToggle: () {
                                                                          final nextStatus =
                                                                              forumState
                                                                                      .isReadOnly
                                                                                  ? 'open'
                                                                                  : 'read_only';
                                                                          cubit
                                                                              .updateForumStatus(
                                                                                  nextStatus);
                                                                          AppSnackBars.showInfo(
                                                                            context,
                                                                            forumState
                                                                                    .isReadOnly
                                                                                ? 'Chat unlocked'
                                                                                : 'Chat locked',
                                                                          );
                                                                        },
                                                                        onSearch: (q) {
                                                                          context
                                                                              .read<
                                                                                  ForumUpdatesCubit>()
                                                                              .setSearchQuery(
                                                                                  q);
                                                                          context
                                                                              .read<
                                                                                  ForumChatCubit>()
                                                                              .setSearchQuery(
                                                                                  q);
                                                                        },
                                                                        onSearchToggle: () {
                                                                          final updatesCubit =
                                                                              context.read<
                                                                                  ForumUpdatesCubit>();
                                                                          final chatCubit =
                                                                              context.read<
                                                                                  ForumChatCubit>();
                                                                          if (updatesCubit
                                                                                  .state
                                                                                  .searchQuery
                                                                                  .isNotEmpty ||
                                                                              chatCubit
                                                                                  .state
                                                                                  .searchQuery
                                                                                  .isNotEmpty) {
                                                                            updatesCubit
                                                                                .setSearchQuery(
                                                                                    '');
                                                                            chatCubit
                                                                                .setSearchQuery(
                                                                                    '');
                                                                          }
                                                                        },
            );
          },
        );
      },
    );
  }
}

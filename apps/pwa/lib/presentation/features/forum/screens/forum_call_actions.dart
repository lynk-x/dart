import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_state.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_chat_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_updates_cubit.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/models/call_participant.dart';
import 'package:lynk_x/presentation/features/forum/services/stream_service.dart';
import 'package:lynk_x/presentation/features/forum/services/mini_overlay_service.dart';
import 'package:lynk_x/presentation/features/forum/services/call_sound_service.dart';
import 'package:lynk_x/presentation/shared/utils/permission_acks.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_cubit.dart';
import 'package:lynk_x/presentation/features/forum/cubit/forum_audio_stream_state.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

// Call and live-stream actions behind the forum header's controls. They used to be inline lambdas
// inside ForumView.build; as plain functions they are readable, and the screen file is no longer
// dominated by call orchestration. Behaviour is unchanged — each body is the original lambda,
// with the values it closed over passed in as parameters.

/// Mutes/unmutes the mic for the active call: the video stream's mic when [isLive], otherwise the
/// audio call's (asking for microphone permission first when un-muting).
/// [onVideoStateChanged] repaints the header, since the video service isn't observable.
void toggleForumMic(
  BuildContext context, {
  required bool isLive,
  required ForumAudioStreamState audioState,
  required ForumAudioStreamCubit audioCubit,
  required VoidCallback onVideoStateChanged,
}) {
  final videoService = ForumVideoStreamService();
  if (isLive) {
    final nextMicMuted =
        !videoService
            .isMicMuted;
    videoService
            .isMicMuted =
        nextMicMuted;
    videoService.toggleMic(
        !nextMicMuted);
    videoService
        .updateParticipantMediaState(
            'host',
            isMicMuted:
                nextMicMuted);
    onVideoStateChanged();
  } else {
    if (audioState
        .isMicMuted) {
      PermissionAcks
          .ensureAcknowledged(
        context,
        PermissionAckType
            .microphone,
        title:
            'Microphone Permission',
        description:
            'To speak in live community streams, Lynk-X needs access to your microphone.',
        icon: Icons
            .mic_rounded,
        actionLabel:
            'Allow Microphone',
        onReady: () =>
            audioCubit
                .toggleMic(),
      );
    } else {
      audioCubit
          .toggleMic();
    }
  }
}

/// Turns the camera on/off for a live video stream (no-op for audio-only calls).
void toggleForumCamera({
  required bool isLive,
  required VoidCallback onVideoStateChanged,
}) {
  final videoService = ForumVideoStreamService();
  if (isLive) {
    final nextCamOn =
        !videoService
            .isCameraOn;
    videoService
            .isCameraOn =
        nextCamOn;
    videoService
        .toggleCamera(
            nextCamOn);
    videoService
        .updateParticipantMediaState(
            'host',
            isCameraOn:
                nextCamOn);
    onVideoStateChanged();
  }
}

/// Ends the host's live video stream or audio call and announces it in chat and updates.
void endForumBroadcast(
  BuildContext context, {
  required ForumState forumState,
  required bool isLive,
  required ForumAudioStreamCubit audioCubit,
}) {
  final name = forumState
          .userName
          .isNotEmpty
      ? forumState
          .userName
      : 'Host';
  // Read cubits before any awaited work below —
  // context shouldn't cross an async gap.
  final chatCubit =
      context.read<
          ForumChatCubit>();
  final updatesCubit =
      context.read<
          ForumUpdatesCubit>();
  AppSnackBars.showInfo(
      context,
      'You ended the call.');

  if (isLive) {
    final videoService =
        ForumVideoStreamService();
    final vfId =
        forumState
            .forumId;
    videoService
        .setMinimized(
            false);
    videoService
        .stopVideoStream();
    videoService
        .setLive(false);
    videoService
        .hostSessionIdNotifier
        .value = null;
    MiniOverlayService()
        .endPipSession();
    // Host is the only
    // party that can
    // reach this branch
    // (only isHost sees
    // the end-broadcast
    // control) — safe to
    // fire-and-forget,
    // local teardown above
    // already happened.
    if (vfId != null &&
        vfId.isNotEmpty) {
      unawaited(
          videoService
              .updateForumStreamingConfig(
        forumId: vfId,
        isLive: false,
      )
              .catchError(
                  (e) {
        debugPrint(
            '[ForumScreen] video end updateForumStreamingConfig failed: $e');
      }));
    }
    final vfSummaryId =
        videoService
            .callSummaryId;
    videoService
            .callSummaryId =
        null;
    unawaited(videoService
        .endCallSummary(
            vfSummaryId));
    // Tells every already-joined listener/co-host
    // the call ended (server already force-closed
    // their forum_call_participants row).
    unawaited(videoService
        .broadcastVideoEvent(
            action:
                'end_stream'));
    unawaited(
        CallSoundService
            .playEnd());

    // Mirrors the "started the live stream"
    // announcement posted on start — without
    // this, isLiveSessionEvent's "ended" text
    // check (updates_tab.dart) never has
    // anything to match, and the JoinCard
    // session-id comparison fix only covers
    // widgets that were mounted to witness the
    // live transition themselves.
    chatCubit
        .sendMessage(
      '$name ended the live stream',
      isOrganizer:
          forumState
              .isOrganizer,
      isPremium:
          forumState
              .isPremium,
      messageType:
          MessageType
              .systemChat,
    );
    updatesCubit
        .sendMessage(
      '$name ended the live stream',
      isOrganizer:
          forumState
              .isOrganizer,
      isPremium:
          forumState
              .isPremium,
      messageType:
          MessageType
              .systemAnnouncement,
    );
  } else {
    audioCubit
        .endAudioStream();

    chatCubit
        .sendMessage(
      '$name ended the live call',
      isOrganizer:
          forumState
              .isOrganizer,
      isPremium:
          forumState
              .isPremium,
      messageType:
          MessageType
              .systemChat,
    );
    updatesCubit
        .sendMessage(
      '$name ended the live call',
      isOrganizer:
          forumState
              .isOrganizer,
      isPremium:
          forumState
              .isPremium,
      messageType:
          MessageType
              .systemAnnouncement,
    );
  }
}

/// Starts a live video stream as host (after camera/mic permission) and announces it.
void startForumLiveStream(
  BuildContext context, {
  required ForumState forumState,
}) {
  final cubit = context.read<ForumCubit>();
  PermissionAcks
      .ensureAcknowledged(
    context,
    PermissionAckType
        .camera,
    title:
        'Host Live Video Stream',
    description:
        'To host a live video stream, Lynk-X needs access to your camera and microphone.',
    icon: Icons
        .videocam_rounded,
    actionLabel:
        'Allow Camera & Mic',
    onReady:
        () async {
      final name = forumState.userName.isNotEmpty
          ? forumState.userName
          : 'Host';
      final vfId =
          forumState.forumId;
      final videoService =
          ForumVideoStreamService();
      videoService.forumId =
          vfId ??
              '';
      // Read cubits before the await below —
      // context shouldn't cross an async gap.
      final chatCubit =
          context.read<ForumChatCubit>();
      final updatesCubit =
          context.read<ForumUpdatesCubit>();
      videoService
          .setLive(true);
      videoService
          .setMinimized(false);
      MiniOverlayService().activateLiveStream(
          hostName:
              name);

      if (vfId !=
              null &&
          vfId.isNotEmpty) {
        final sessionId =
            await videoService.createCloudflareSession(vfId);
        if (sessionId ==
            null) {
          videoService.setLive(false);
          MiniOverlayService().endPipSession();
          if (context.mounted) {
            AppSnackBars.showError(context, 'Could not start your Cloudflare session — please try again.');
          }
          return;
        }
        // The HOST's own session IS the host
        // session — keeps hostSessionIdNotifier
        // (used by _LiveStreamJoinCard's
        // end-detection fast path) current for
        // the host too, not just listeners/
        // co-hosts (see subscribeToRemoteVideo's
        // own comment).
        videoService
            .hostSessionIdNotifier
            .value = sessionId;

        // Call-summary row must exist BEFORE
        // joinAsCallParticipant (needs its id) and
        // before updateForumStreamingConfig (which
        // now carries it, so any later client can
        // discover it) — see ForumAudioStreamCubit
        // .startAudioStream for the matching audio
        // reordering and full rationale.
        String?
            callSummaryId;
        final vfCreatedAt =
            forumState.forumCreatedAt;
        if (vfCreatedAt !=
            null) {
          callSummaryId =
              await videoService.startCallSummary(
            forumId: vfId,
            forumCreatedAt: vfCreatedAt,
            hostId: cubit.userId,
            sessionId: sessionId,
          );
          videoService.callSummaryId =
              callSummaryId;
        }

        // The host claims their own speaker slot
        // the same way a co-host does — see
        // social.join_as_call_participant's doc
        // comment for why there is no separate
        // host-registration path.
        if (callSummaryId !=
            null) {
          await videoService.joinAsCallParticipant(
            forumId: vfId,
            callSummaryId: callSummaryId,
            cfSessionId: sessionId,
            trackName: cubit.userId,
          );
          videoService.participantsNotifier.value =
              {
            cubit.userId: CallParticipant(
              userId: cubit.userId,
              userName: name,
              cfSessionId: sessionId,
              trackName: cubit.userId,
            ),
          };
        }

        try {
          await videoService.updateForumStreamingConfig(
            forumId: vfId,
            isLive: true,
            sessionId: sessionId,
            hostId: cubit.userId,
            callSummaryId: callSummaryId,
          );
        } catch (e) {
          debugPrint('[ForumScreen] video updateForumStreamingConfig failed: $e');
        }
      }

      chatCubit
          .sendMessage(
        '$name started the live stream',
        isOrganizer:
            forumState.isOrganizer,
        isPremium:
            forumState.isPremium,
        messageType:
            MessageType.systemChat,
      );
      updatesCubit
          .sendMessage(
        '$name started the live stream',
        isOrganizer:
            forumState.isOrganizer,
        isPremium:
            forumState.isPremium,
        messageType:
            MessageType.systemAnnouncement,
      );
    },
  );
}

/// Starts a live audio call as host (after microphone permission) and announces it.
void startForumAudioStream(
  BuildContext context, {
  required ForumState forumState,
  required ForumAudioStreamCubit audioCubit,
}) {
  PermissionAcks
      .ensureAcknowledged(
    context,
    PermissionAckType
        .microphone,
    title:
        'Host Audio Stream',
    description:
        'To start a live audio stream and speak with attendees, Lynk-X needs access to your microphone.',
    icon: Icons
        .mic_rounded,
    actionLabel:
        'Allow Microphone',
    onReady:
        () {
      final name = forumState.userName.isNotEmpty
          ? forumState.userName
          : 'Host';
      MiniOverlayService().activateLiveCall(
          hostName:
              name);
      audioCubit
          .startAudioStream();
      context
          .read<ForumChatCubit>()
          .sendMessage(
            '$name started the live call',
            isOrganizer: forumState.isOrganizer,
            isPremium: forumState.isPremium,
            messageType: MessageType.systemChat,
          );
      context
          .read<ForumUpdatesCubit>()
          .sendMessage(
            '$name started the live call',
            isOrganizer: forumState.isOrganizer,
            isPremium: forumState.isPremium,
            messageType: MessageType.systemAnnouncement,
          );
    },
  );
}

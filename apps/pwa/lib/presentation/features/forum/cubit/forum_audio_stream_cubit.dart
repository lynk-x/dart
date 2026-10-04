import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_participant.dart';
import '../services/call_sound_service.dart';
import '../services/forum_audio_stream_service.dart';
import '../services/mini_overlay_service.dart';
import '../widgets/header.dart';
import 'forum_audio_stream_state.dart';

class ForumAudioStreamCubit extends Cubit<ForumAudioStreamState> {
  final ForumAudioStreamService service;
  final String forumId;
  final DateTime? forumCreatedAt;
  final String userId;
  String userName;
  final bool isOrganizer;

  /// Id of the social.forum_call_summaries row for the call this cubit is
  /// currently hosting — set by startAudioStream(), consumed by
  /// endAudioStream() to close it out and by _reconnectPublish() (needs it
  /// to update this host's own forum_call_participants row). Null when not
  /// hosting, or when the insert itself failed (call-summary writes are
  /// best-effort, not critical-path — see
  /// ForumAudioStreamService.startCallSummary).
  String? _callSummaryId;

  ForumAudioStreamCubit({
    required this.service,
    required this.forumId,
    this.forumCreatedAt,
    required this.userId,
    required this.userName,
    this.isOrganizer = false,
  }) : super(const ForumAudioStreamState()) {
    // Fires when the JS layer's bounded reconnect (3 attempts) for a
    // dropped listener connection gives up — surfaces it the same way
    // every other audio-stream failure reaches the user, via errorMessage.
    service.onRemoteAudioListenerLost(() {
      if (isClosed || state.role == ForumHeaderRole.host) return;
      emit(state.copyWith(
        errorMessage: 'Lost connection to the live call. Tap to rejoin.',
      ));
    });

    // Publish-side counterpart: the JS publish connection detected ICE
    // failure/disconnect. Unlike the listener side, JS can't recover this
    // itself — Cloudflare's own guidance is to replace the connection
    // (a NEW session), which needs a Supabase-authenticated session-create
    // call, so the actual reconnect sequence runs here, not in JS. This
    // fires for whichever role is currently publishing through THIS
    // cubit instance's own peer connection — the host and every co-host
    // each run their own ForumAudioStreamCubit, so "is this cubit
    // currently publishing" is "host OR speaker", not host-only (a
    // co-host's dropped connection used to be silently ignored here).
    service.onPublishNeedsReconnect(() {
      if (isClosed || !_isPublishingRole) return;
      unawaited(_reconnectPublish());
    });
    service.onPublishLost(() {
      if (isClosed || !_isPublishingRole) return;
      emit(state.copyWith(
        errorMessage: state.role == ForumHeaderRole.host
            ? 'Lost connection to your live call. Please end and restart it.'
            : 'Lost connection to your speaking slot. Please rejoin as a speaker.',
      ));
    });

    // React to isLive/role transitions from ANY of the several emit sites
    // (start_stream, initial sync, joinAudioStream, end_stream) rather than
    // threading timer start/stop calls through each one individually.
    _telemetrySub = stream.listen((s) {
      if (s.isLive && s.role != ForumHeaderRole.host) {
        _startTelemetryPolling();
      } else {
        _stopTelemetryPolling();
      }
    });
  }

  Timer? _telemetryTimer;
  StreamSubscription<ForumAudioStreamState>? _telemetrySub;

  void _startTelemetryPolling() {
    if (_telemetryTimer != null) return;
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      service.fetchListenerTelemetryStats();
    });
  }

  void _stopTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void updateUserName(String newName) {
    userName = newName;
  }

  /// Clears a one-shot error message after it's been shown to the user, so
  /// an identical subsequent failure (e.g. denying mic permission twice)
  /// still registers as a state change for listeners keyed on errorMessage.
  void clearAudioStreamError() {
    if (state.errorMessage == null) return;
    emit(state.copyWith(errorMessage: null));
  }

  bool _isJoiningOrStarting = false;
  bool _isTogglingMic = false;

  /// Initializes Supabase Realtime channel subscription & initial state fetch
  Future<void> initRealtimeSubscription() async {
    await _subscribeAndSyncState();
  }

  Future<void> _subscribeAndSyncState() async {
    service.subscribeToAudioBroadcast(
      forumId: forumId,
      onEvent: _handleAudioEvent,
      onStatusChange: (status) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!state.isLive) return;

          // Hosts lose their ability to broadcast start/end/participant
          // events over this channel just like listeners lose their
          // ability to receive them — a disconnected host silently stops
          // notifying anyone the call ended, so this can't be
          // listener-only.
          if (state.role != ForumHeaderRole.host) {
            service.unsubscribeFromRemoteAudio();
          }
          service.clearMediaSession();
          MiniOverlayService().endPipSession();
          emit(state.copyWith(
            isLive: false,
            errorMessage: state.role == ForumHeaderRole.host
                ? 'Connection lost. Your live call has ended — start a new one to continue.'
                : 'Audio stream disconnected.',
          ));
        }
      },
    );

    // Initial state check for active live stream when user opens the forum
    final config = await service.fetchInitialStreamingConfig(forumId);
    if (isClosed) return;

    if (config != null) {
      final isLive = config['is_live'] == true;
      final hostId = config['active_host_id'] as String?;
      final sessionId = config['cf_session_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      final isHost = hostId == userId;

      if (isLive) {
        if (!state.isLive) {
          service.configureMediaSession(
            title: 'Lynk-X Live Audio Stream',
            artist: isHost ? userName : 'Community Stream',
          );
          if (isHost) service.requestWakeLock();

          MiniOverlayService().activateLiveCall(hostName: isHost ? userName : 'Host');

          // Every client's cubit — not just the host's — needs this to
          // support joinAsCoHost()/leaveCoHost(), which target the active
          // call's participant registry regardless of who's viewing.
          _callSummaryId = callSummaryId;

          // Bootstrap the participant registry — co-hosts beyond the one
          // this client might already know about (e.g. opening the forum
          // well after the call started and others have since joined).
          final participants = callSummaryId != null
              ? await service.fetchCallParticipants(callSummaryId)
              : <String, CallParticipant>{};
          if (isClosed) return;

          emit(state.copyWith(
            isLive: true,
            role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
            sessionId: sessionId,
            participants: participants,
            isMicMuted: !isHost,
            isBroadcastMuted: false,
          ));

          // Local join feedback — this whole branch only runs while
          // state.isLive was false (the enclosing `if (!state.isLive)`
          // above), so it's always a genuine discovery: opening the forum
          // (or reopening the app) to find a call already in progress,
          // for host and listener alike.
          unawaited(CallSoundService.playJoin());

          // The host's own publish flow already owns their peer connection
          // (startAudioStream); only a listener needs to pull the host's
          // track down. sessionId can be null here only if the host wrote
          // streaming_config before session creation resolved — nothing to
          // subscribe to yet in that case.
          if (!isHost && sessionId != null) {
            unawaited(_pullAllParticipantTracks(
              hostSessionId: sessionId,
              participants: participants,
            ));
          }
        }
      } else {
        // Stream explicitly not live according to config
        service.unsubscribeFromRemoteAudio();
        service.clearMediaSession();
        MiniOverlayService().endPipSession();

        emit(const ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: {},
          isMicMuted: true,
          isBroadcastMuted: false,
        ));
      }
    } else if (state.isLive && state.role != ForumHeaderRole.host) {
      service.unsubscribeFromRemoteAudio();
      service.clearMediaSession();
      MiniOverlayService().endPipSession();
      emit(state.copyWith(isLive: false));
    }
  }

  /// Listener-only bootstrap: establishes the listener connection against
  /// the host's track first (subscribeToRemoteAudio, which CREATES the
  /// connection), then adds every OTHER active participant's track into
  /// that same connection (addParticipantTrack, which requires one to
  /// already exist — see lynkAudioStreamHelper.addParticipantTrack). Used
  /// whenever a listener discovers a call already has co-hosts present
  /// (opening the forum well after the call started, or joining
  /// mid-call), not just the common case of a call that only ever had the
  /// host speaking.
  Future<void> _pullAllParticipantTracks({
    required String hostSessionId,
    required Map<String, CallParticipant> participants,
  }) async {
    final success = await service.subscribeToRemoteAudio(
      forumId: forumId,
      hostSessionId: hostSessionId,
    );
    if (isClosed || !success) return;

    for (final participant in participants.values) {
      if (participant.userId == userId) continue;
      // The host's own track was just pulled above via subscribeToRemoteAudio
      // (which always targets streaming_config's cf_session_id/active_host_id
      // — the host's address, by definition the same one participant.cfSessionId
      // would resolve to for the host's own registry row), so skip it here
      // to avoid a redundant/conflicting second pull of the same track.
      if (participant.cfSessionId == hostSessionId) continue;
      await service.addParticipantTrack(
        forumId: forumId,
        participantUserId: participant.userId,
        remoteSessionId: participant.cfSessionId,
        remoteTrackName: participant.trackName,
      );
    }
  }

  void _handleAudioEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'start_stream':
        final sessionId = payload['sessionId'] as String?;
        final hostId = payload['hostId'] as String?;
        final hostName = payload['hostName'] as String?;
        final isHost = hostId == userId;
        // Captured BEFORE the emit below flips it to true — distinguishes
        // a genuine first join (this listener/host was not live a moment
        // ago) from the host's own reconnect echo (start_stream is also
        // broadcast by _reconnectPublish for the SAME call; state.isLive
        // never dropped on a listener for that case, since the listener
        // never knew the host's publish connection failed).
        final wasAlreadyLive = state.isLive;
        // Not overwritten for the host's own cubit instance — it already
        // set this itself inside startAudioStream(), before this
        // broadcast was even sent.
        if (!isHost) {
          _callSummaryId = payload['callSummaryId'] as String?;
        }

        // The host's own registry entry rides along on start_stream so a
        // listener has it immediately, without a separate round trip —
        // same (sessionId, trackName) address a direct fetchCallParticipants
        // would return for the host's row.
        final hostParticipant = (hostId != null && sessionId != null)
            ? CallParticipant(
                userId: hostId,
                userName: hostName ?? 'Host',
                cfSessionId: sessionId,
                trackName: hostId,
              )
            : null;

        service.configureMediaSession(
          title: 'Lynk-X Live Audio Stream',
          artist: isHost ? userName : (hostName ?? 'Community Stream'),
        );

        MiniOverlayService().activateLiveCall(
          hostName: isHost ? userName : (hostName ?? 'Host'),
        );

        emit(state.copyWith(
          isLive: true,
          role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
          sessionId: sessionId,
          participants: hostParticipant != null ? {hostParticipant.userId: hostParticipant} : const {},
          isMicMuted: !isHost,
          isBroadcastMuted: false,
        ));

        // Local join feedback — only for a LISTENER discovering the call
        // just went live while they were already in the forum; the host's
        // own join sound plays locally from startAudioStream() instead
        // (fires immediately there rather than waiting for this broadcast
        // to round-trip back). !wasAlreadyLive excludes the host's own
        // reconnect echo, which also uses 'start_stream' for the same
        // already-live call.
        if (!isHost && !wasAlreadyLive) {
          unawaited(CallSoundService.playJoin());
        }

        // The broadcaster's own startAudioStream() already owns publishing
        // its track; a listener needs to pull it down to actually hear it.
        if (!isHost && sessionId != null) {
          unawaited(service.subscribeToRemoteAudio(
            forumId: forumId,
            hostSessionId: sessionId,
          ));
        }
        break;

      case 'end_stream':
        service.unsubscribeFromRemoteAudio();
        service.clearMediaSession();
        MiniOverlayService().endPipSession();

        emit(const ForumAudioStreamState(
          isLive: false,
          role: ForumHeaderRole.listener,
          participants: {},
          isMicMuted: true,
          isBroadcastMuted: false,
        ));

        // Everyone on the call hears this — the one call-lifecycle tone
        // that stays broadcast-driven rather than local-only (unlike
        // call_join, which only plays for whoever just started/joined).
        unawaited(CallSoundService.playEnd());
        break;

      // A co-host joined the call's participant registry (the host's own
      // initial join rides on start_stream above instead — this fires for
      // every OTHER participant, host included broadcasting about a
      // co-host). Listeners reactively pull the new participant's track
      // into their already-live connection; the host/other co-hosts only
      // need the registry update (they don't pull anyone's audio — only
      // the host ever publishes today... once co-hosts can publish too,
      // they'd pull each other the same way a listener does, which this
      // role-based branch already covers via "not this user's own join").
      case 'participant_joined':
        final participant = CallParticipant.fromJson(payload);
        if (participant.userId.isEmpty || participant.userId == userId) return;
        final updated = Map<String, CallParticipant>.from(state.participants);
        updated[participant.userId] = participant;
        emit(state.copyWith(participants: updated));

        if (state.role != ForumHeaderRole.host) {
          unawaited(service.addParticipantTrack(
            forumId: forumId,
            participantUserId: participant.userId,
            remoteSessionId: participant.cfSessionId,
            remoteTrackName: participant.trackName,
          ));
        }
        break;

      case 'participant_left':
        final leftUserId = payload['userId'] as String?;
        if (leftUserId == null || !state.participants.containsKey(leftUserId)) return;
        final updated = Map<String, CallParticipant>.from(state.participants)
          ..remove(leftUserId);
        emit(state.copyWith(participants: updated));
        service.removeParticipantTrack(leftUserId);
        break;

      // Targeted at one specific user (payload['targetUserId']) — every
      // other client's cubit also receives this broadcast (the channel is
      // forum-wide) but ignores it, since Supabase Realtime broadcast has
      // no per-recipient filtering server-side. See
      // social.invite_call_participant's doc comment for why the host
      // can't just unilaterally register a participant — the host has no
      // way to create a Cloudflare session or publish a track on someone
      // else's behalf (can't access their mic), so this only ever
      // notifies; the actual publish happens in acceptSpeakerInvite(),
      // self-initiated by the invitee once they accept.
      case 'participant_invite':
        final targetUserId = payload['targetUserId'] as String?;
        if (targetUserId != userId) return;
        final fromHostName = payload['fromHostName'] as String?;
        emit(state.copyWith(pendingInviteFromHostName: fromHostName ?? 'The host'));
        break;

      // The invitee accepted and already published their own track —
      // host-only: registers it via invite_speaker (the one RPC call only
      // an organizer can make), then re-broadcasts participant_joined so
      // everyone (invitee included) converges on the same registry state
      // participant_joined's own handler above already knows how to apply.
      case 'participant_invite_accepted':
        if (state.role != ForumHeaderRole.host) return;
        unawaited(_registerAcceptedInvite(payload));
        break;
    }
  }

  Future<void> _registerAcceptedInvite(Map<String, dynamic> payload) async {
    final callSummaryId = _callSummaryId;
    if (callSummaryId == null) return;
    final participant = CallParticipant.fromJson(payload);
    if (participant.userId.isEmpty) return;

    final participantId = await service.inviteCallParticipant(
      forumId: forumId,
      callSummaryId: callSummaryId,
      targetUserId: participant.userId,
      cfSessionId: participant.cfSessionId,
      trackName: participant.trackName,
    );
    if (participantId == null) {
      // Cap was hit between the invite being sent and the invitee
      // accepting, or some other rejection — nothing more this cubit can
      // do for the invitee's side (their own publish already succeeded,
      // but it will simply never be added to the registry listeners
      // pull from). Surfacing this to the inviter rather than silently
      // dropping it.
      emit(state.copyWith(errorMessage: 'Could not add ${participant.userName} as a speaker — the call may be full.'));
      return;
    }

    final updated = Map<String, CallParticipant>.from(state.participants);
    updated[participant.userId] = participant;
    emit(state.copyWith(participants: updated));

    await service.broadcastAudioEvent(
      action: 'participant_joined',
      extraData: participant.toBroadcastPayload(),
    );
  }

  /// Accepts a pending "invited to speak" prompt (state
  /// .pendingInviteFromHostName) — runs the same publish sequence
  /// joinAsCoHost() does (mic -> session -> publish), but reports the
  /// result back to the host via participant_invite_accepted instead of
  /// calling join_as_call_participant directly, since an invited
  /// non-organizer member isn't eligible to call that RPC themselves —
  /// only the inviting host can register them (social.invite_speaker).
  Future<bool> acceptSpeakerInvite() async {
    if (state.pendingInviteFromHostName == null || _isJoiningAsCoHost) {
      return false;
    }
    _isJoiningAsCoHost = true;
    try {
      emit(state.copyWith(clearPendingInvite: true));

      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(errorMessage: 'Microphone access is required to speak.'));
        return false;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        emit(state.copyWith(errorMessage: 'Could not start your speaker session — please try again.'));
        return false;
      }

      final published = await service.publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        emit(state.copyWith(errorMessage: 'Could not publish your audio — please try again.'));
        return false;
      }

      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );

      emit(state.copyWith(role: ForumHeaderRole.speaker, isMicMuted: false));
      service.requestWakeLock();

      await service.broadcastAudioEvent(
        action: 'participant_invite_accepted',
        extraData: selfParticipant.toBroadcastPayload(),
      );
      return true;
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] acceptSpeakerInvite error: $e');
      emit(state.copyWith(errorMessage: 'Could not join as a speaker: $e'));
      return false;
    } finally {
      _isJoiningAsCoHost = false;
    }
  }

  void declineSpeakerInvite() {
    if (state.pendingInviteFromHostName == null) return;
    emit(state.copyWith(clearPendingInvite: true));
  }

  /// Host/organizer-only — sends a "you're invited to speak" prompt to
  /// [targetUserId]. Does NOT itself grant a speaking slot (see
  /// social.invite_speaker's doc comment) — only the invitee's own
  /// acceptSpeakerInvite() can actually publish their track; this just
  /// starts that conversation.
  Future<void> inviteSpeaker(String targetUserId) async {
    if (state.role != ForumHeaderRole.host) return;
    await service.broadcastAudioEvent(
      action: 'participant_invite',
      extraData: {'targetUserId': targetUserId, 'fromHostName': userName},
    );
  }

  /// Joins an ongoing live audio call as a listener. Only reachable in the
  /// narrow window before the cubit's own auto-sync (_subscribeAndSyncState /
  /// _handleAudioEvent) has caught up — the Join Card disables its own tap
  /// target once state.isLive is true (see updates_tab.dart), which happens
  /// automatically the moment auto-sync resolves. Re-fetches streaming_config
  /// itself (rather than trusting a sessionId passed in — the caller, the
  /// Join Card, never has one) so the actual subscribe call below has a real
  /// session to pull from instead of emitting isLive:true with nothing
  /// behind it.
  Future<void> joinAudioStream({String? hostName}) async {
    if (state.isLive || _isJoiningOrStarting) return;
    _isJoiningOrStarting = true;

    try {
      final config = await service.fetchInitialStreamingConfig(forumId);
      if (isClosed || state.isLive) return;
      if (config == null || config['is_live'] != true) return;

      final sessionId = config['cf_session_id'] as String?;
      final hostId = config['active_host_id'] as String?;
      final callSummaryId = config['call_summary_id'] as String?;
      final isHost = hostId == userId;
      final hName = hostName ?? 'Host';

      service.configureMediaSession(
        title: 'Lynk-X Live Audio Stream',
        artist: isHost ? userName : hName,
      );
      MiniOverlayService().activateLiveCall(hostName: isHost ? userName : hName);

      _callSummaryId = callSummaryId;

      final participants = callSummaryId != null
          ? await service.fetchCallParticipants(callSummaryId)
          : <String, CallParticipant>{};
      if (isClosed || state.isLive) return;

      emit(state.copyWith(
        isLive: true,
        role: isHost ? ForumHeaderRole.host : ForumHeaderRole.listener,
        sessionId: sessionId,
        participants: participants,
        isMicMuted: !isHost,
        isBroadcastMuted: false,
      ));

      // Local join feedback — this method is only ever reached while
      // state.isLive was false (checked at entry and again just above),
      // so this is always a genuine join, never a resync/reconnect echo.
      unawaited(CallSoundService.playJoin());

      if (!isHost && sessionId != null) {
        await _pullAllParticipantTracks(
          hostSessionId: sessionId,
          participants: participants,
        );
      }
    } finally {
      _isJoiningOrStarting = false;
    }
  }

  /// Starts a new live Audio Stream (Invoked by organizer/user double tap)
  Future<void> startAudioStream() async {
    if (state.isLive || _isJoiningOrStarting) return;
    _isJoiningOrStarting = true;

    try {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        MiniOverlayService().endPipSession();
        emit(state.copyWith(
          isLive: false,
          errorMessage: 'Microphone access is required to host a live audio stream.',
        ));
        return;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        throw StateError('Could not start your Cloudflare session — please try again.');
      }

      final published = await service.publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        throw StateError('Could not publish your audio — please try again.');
      }

      // Call-summary row must exist BEFORE joinAsCallParticipant (which
      // needs its id) and before updateForumStreamingConfig (which now
      // carries it, so any later client can discover it) — moved ahead of
      // both, unlike before the participant registry existed. Aggregate
      // history only, not otherwise critical-path, but now load-bearing
      // for the registry itself, so a failure here does abort the start.
      final createdAt = forumCreatedAt;
      if (createdAt == null) {
        throw StateError('forumCreatedAt is required to start a call.');
      }
      _callSummaryId = await service.startCallSummary(
        forumId: forumId,
        forumCreatedAt: createdAt,
        hostId: userId,
        sessionId: sessionId,
      );
      final callSummaryId = _callSummaryId;
      if (callSummaryId == null) {
        throw StateError('Could not start the call — please try again.');
      }

      // The host claims their own participant slot the same way a
      // co-host does — see social.join_as_call_participant's doc comment
      // for why there is no separate host-registration path.
      await service.joinAsCallParticipant(
        forumId: forumId,
        callSummaryId: callSummaryId,
        cfSessionId: sessionId,
        trackName: userId,
      );

      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: true,
        sessionId: sessionId,
        hostId: userId,
        callSummaryId: callSummaryId,
      );

      final hostParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );

      service.configureMediaSession(
        title: 'Lynk-X Live Audio Stream',
        artist: '$userName (Host)',
      );
      service.requestWakeLock();

      MiniOverlayService().activateLiveCall(hostName: userName);

      emit(state.copyWith(
        isLive: true,
        role: ForumHeaderRole.host,
        sessionId: sessionId,
        participants: {hostParticipant.userId: hostParticipant},
        isMicMuted: false,
        isBroadcastMuted: false,
      ));

      // Local join feedback for the host — fires immediately rather than
      // waiting for the start_stream broadcast below to round-trip back
      // through this same cubit's _handleAudioEvent.
      unawaited(CallSoundService.playJoin());

      // Broadcast start_stream to all connected attendees via WebSocket —
      // carries the host's own CallParticipant so a listener's
      // _handleAudioEvent can seed its registry without a separate fetch,
      // and callSummaryId so joinAsCoHost()/leaveCoHost() work for
      // clients that are already live-watching (not freshly bootstrapping
      // via fetchInitialStreamingConfig).
      await service.broadcastAudioEvent(
        action: 'start_stream',
        sessionId: sessionId,
        hostId: userId,
        extraData: {'hostName': userName, 'callSummaryId': callSummaryId},
      );
    } catch (e) {
      service.stopLocalMicrophone();
      service.clearMediaSession();
      MiniOverlayService().endPipSession();
      emit(state.copyWith(
        isLive: false,
        errorMessage: 'Failed to start audio stream: $e',
      ));
    } finally {
      _isJoiningOrStarting = false;
    }
  }

  /// Ends an active Audio Stream (Invoked by host tapping stop button)
  Future<void> endAudioStream() async {
    if (!state.isLive) return;

    // Stop local audio hardware immediately — no reason to keep the mic hot
    // while the network call below is in flight.
    service.stopLocalMicrophone();

    try {
      await service.updateForumStreamingConfig(
        forumId: forumId,
        isLive: false,
      );

      // Broadcast end_stream to all connected attendees via WebSocket
      await service.broadcastAudioEvent(
        action: 'end_stream',
        hostId: userId,
      );
    } catch (e) {
      // Server never learned the call ended: keep local state live (with the
      // mic already stopped, matching a muted host) instead of showing
      // "ended" locally while listeners and a later config fetch would still
      // see is_live: true — that mismatch was silently stranding listeners
      // and reviving the call out from under the host on their next visit.
      debugPrint('[ForumAudioStreamCubit] endAudioStream network sync error: $e');
      emit(state.copyWith(
        isMicMuted: true,
        errorMessage: 'Could not end the call — check your connection and try again.',
      ));
      return;
    }

    service.clearMediaSession();
    MiniOverlayService().endPipSession();

    await service.endCallSummary(_callSummaryId);
    _callSummaryId = null;

    emit(const ForumAudioStreamState(
      isLive: false,
      role: ForumHeaderRole.listener,
      participants: {},
      isMicMuted: true,
      isBroadcastMuted: false,
    ));
  }

  /// Toggles local microphone mute/unmute state. No longer touches the
  /// participant registry — holding a slot and being audibly unmuted are
  /// separate concerns now (see CallParticipant/ForumAudioStreamState
  /// docs); muting doesn't remove this user from state.participants, it
  /// only silences their published track via toggleMicEnabled's
  /// replaceTrack swap.
  Future<void> toggleMic() async {
    if (_isTogglingMic) return;
    _isTogglingMic = true;

    try {
      final nextMuted = !state.isMicMuted;

      if (nextMuted) {
        // toggleMicEnabled (not stopLocalMicrophone) — if this is the host
        // and the track is actively published to Cloudflare, this swaps
        // the sender's track to null via replaceTrack() rather than
        // stopping the local MediaStreamTrack outright, which would kill
        // the Cloudflare publish for good (a later unmute's fresh track
        // from startLocalMicrophone() is never reattached to the
        // already-negotiated sender). No-op if nothing is published yet.
        await service.toggleMicEnabled(false);
      } else {
        // Only (re)acquire the mic if it isn't already captured — mute no
        // longer stops the local track (see toggleMicEnabled above), so on
        // a normal unmute it's still live and startLocalMicrophone() must
        // NOT be called again here: that function stops-and-replaces
        // whatever stream it's handed if one already exists, which would
        // kill the very track toggleMicEnabled(true) is about to resume
        // sending — turning this fix into the same bug one step later.
        if (!service.hasLocalMicrophone) {
          final micGranted = await service.startLocalMicrophone();
          if (!micGranted) {
            emit(state.copyWith(
              errorMessage: 'Microphone access is required to speak.',
            ));
            return;
          }
        }
        await service.toggleMicEnabled(true);
        service.requestWakeLock();
      }

      emit(state.copyWith(isMicMuted: nextMuted));
    } finally {
      _isTogglingMic = false;
    }
  }

  /// Toggles broadcast audio output mute/unmute state for listeners
  void toggleBroadcastMute() {
    final nextMuted = !state.isBroadcastMuted;
    service.setBroadcastMuted(nextMuted);
    emit(state.copyWith(
      isBroadcastMuted: nextMuted,
    ));
  }

  bool _isJoiningAsCoHost = false;

  /// Self-serve: an eligible organizer (not the original host — they're
  /// already a participant via startAudioStream) joins the call as a
  /// co-host. Mirrors startAudioStream's publish sequence (mic -> session
  /// -> publish -> join_as_call_participant) but does NOT touch
  /// streaming_config — that still correctly points at the original
  /// host's address; this user is an ADDITIONAL participant, not a
  /// replacement. social.join_as_call_participant itself enforces the
  /// organizer-role check and the speaker cap — this method surfaces
  /// whichever of those rejections applies as errorMessage, same pattern
  /// as every other failure path in this cubit.
  Future<bool> joinAsCoHost() async {
    if (_isJoiningAsCoHost || !state.isLive || state.role == ForumHeaderRole.host) {
      return false;
    }
    final callSummaryId = _callSummaryId;
    if (callSummaryId == null) {
      emit(state.copyWith(errorMessage: 'Could not join — call details are still loading.'));
      return false;
    }

    _isJoiningAsCoHost = true;
    try {
      final micGranted = await service.startLocalMicrophone();
      if (!micGranted) {
        emit(state.copyWith(errorMessage: 'Microphone access is required to join as a speaker.'));
        return false;
      }

      final sessionId = await service.createCloudflareSession(forumId);
      if (sessionId == null) {
        emit(state.copyWith(errorMessage: 'Could not start your speaker session — please try again.'));
        return false;
      }

      final published = await service.publishCloudflareTracks(forumId, sessionId, trackName: userId);
      if (!published) {
        emit(state.copyWith(errorMessage: 'Could not publish your audio — please try again.'));
        return false;
      }

      final participantId = await service.joinAsCallParticipant(
        forumId: forumId,
        callSummaryId: callSummaryId,
        cfSessionId: sessionId,
        trackName: userId,
      );
      if (participantId == null) {
        service.stopLocalMicrophone();
        emit(state.copyWith(errorMessage: 'This call already has the maximum number of speakers.'));
        return false;
      }

      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: sessionId,
        trackName: userId,
      );
      final updatedParticipants = Map<String, CallParticipant>.from(state.participants);
      updatedParticipants[userId] = selfParticipant;

      emit(state.copyWith(
        role: ForumHeaderRole.speaker,
        participants: updatedParticipants,
        isMicMuted: false,
      ));
      service.requestWakeLock();

      await service.broadcastAudioEvent(
        action: 'participant_joined',
        extraData: selfParticipant.toBroadcastPayload(),
      );

      // From here on, this cubit instance's _isPublishingRole is true, so
      // onPublishNeedsReconnect/onPublishLost (registered in the
      // constructor) will drive _reconnectPublish for this co-host's own
      // connection exactly as they already do for the host.
      return true;
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] joinAsCoHost error: $e');
      emit(state.copyWith(errorMessage: 'Could not join as a speaker: $e'));
      return false;
    } finally {
      _isJoiningAsCoHost = false;
    }
  }

  /// Self-serve: a co-host (not the original host — they use
  /// endAudioStream) leaves their speaking slot.
  Future<void> leaveCoHost() async {
    if (state.role != ForumHeaderRole.speaker) return;
    final callSummaryId = _callSummaryId;

    service.stopLocalMicrophone();
    service.releaseWakeLock();

    if (callSummaryId != null) {
      await service.leaveCallParticipant(callSummaryId);
    }

    final updatedParticipants = Map<String, CallParticipant>.from(state.participants)..remove(userId);
    emit(state.copyWith(
      role: ForumHeaderRole.listener,
      participants: updatedParticipants,
      isMicMuted: true,
    ));

    await service.broadcastAudioEvent(
      action: 'participant_left',
      extraData: {'userId': userId},
    );
  }

  bool _isReconnectingPublish = false;

  /// Whether this cubit instance currently owns the publish side of
  /// service's peer connection — true for the host AND for a co-host,
  /// since each runs its own ForumAudioStreamCubit/ForumAudioStreamService
  /// pair with an independent Cloudflare publish connection. A listener
  /// never publishes, so has nothing for onPublishNeedsReconnect/
  /// onPublishLost to act on.
  bool get _isPublishingRole =>
      state.role == ForumHeaderRole.host || state.role == ForumHeaderRole.speaker;

  /// Recovers this user's own publish connection after the JS layer
  /// detects ICE failure/disconnect (see service.onPublishNeedsReconnect).
  /// Per Cloudflare's own guidance there is no supported same-session
  /// recovery for a publisher, so this replaces the connection entirely: a
  /// NEW Cloudflare session, republished tracks, the new session id
  /// persisted to this user's own forum_call_participants row (the source
  /// of truth every participant, including the host, actually lives in).
  ///
  /// The HOST additionally owns streaming_config.cf_session_id — the
  /// well-known address every listener's OWN base connection
  /// (joinAsListener) was built against — so only the host's reconnect
  /// updates it and broadcasts 'start_stream', which _handleAudioEvent's
  /// 'start_stream' case already unconditionally re-subscribes a listener
  /// against, rebuilding their whole connection. A co-host's reconnect
  /// instead re-broadcasts 'participant_joined' with the new session —
  /// the SAME event a first-time join uses — so already-connected
  /// listeners just re-run addParticipantTrack against the new session
  /// (their base connection, pulling the host, is untouched and still
  /// healthy; only this one co-host's track needs re-pulling).
  Future<void> _reconnectPublish() async {
    if (_isReconnectingPublish || !state.isLive || !_isPublishingRole) {
      return;
    }
    final isHost = state.role == ForumHeaderRole.host;
    final callSummaryId = _callSummaryId;
    _isReconnectingPublish = true;
    try {
      final newSessionId = await service.createCloudflareSession(forumId);
      if (isClosed || newSessionId == null) return;

      final published = await service.publishCloudflareTracks(
        forumId,
        newSessionId,
        forceReconnect: true,
        trackName: userId,
      );
      if (isClosed || !published) return;

      if (isHost) {
        await service.updateForumStreamingConfig(
          forumId: forumId,
          isLive: true,
          sessionId: newSessionId,
          hostId: userId,
          callSummaryId: callSummaryId,
        );
      }
      if (callSummaryId != null) {
        await service.updateParticipantSession(
          callSummaryId: callSummaryId,
          cfSessionId: newSessionId,
          trackName: userId,
        );
      }
      if (isClosed) return;

      final updatedParticipants = Map<String, CallParticipant>.from(state.participants);
      final selfParticipant = CallParticipant(
        userId: userId,
        userName: userName,
        cfSessionId: newSessionId,
        trackName: userId,
      );
      updatedParticipants[userId] = selfParticipant;
      emit(state.copyWith(sessionId: newSessionId, participants: updatedParticipants));

      if (isHost) {
        await service.broadcastAudioEvent(
          action: 'start_stream',
          sessionId: newSessionId,
          hostId: userId,
          extraData: {'hostName': userName, 'callSummaryId': callSummaryId},
        );
      } else {
        await service.broadcastAudioEvent(
          action: 'participant_joined',
          extraData: selfParticipant.toBroadcastPayload(),
        );
      }
    } catch (e) {
      debugPrint('[ForumAudioStreamCubit] _reconnectPublish error: $e');
    } finally {
      _isReconnectingPublish = false;
    }
  }

  @override
  Future<void> close() async {
    _telemetrySub?.cancel();
    _stopTelemetryPolling();
    service.removeListenerLostCallback();
    service.removePublishReconnectCallbacks();
    service.stopLocalMicrophone();
    if (state.role != ForumHeaderRole.host) {
      service.unsubscribeFromRemoteAudio();
    }
    service.clearMediaSession();
    MiniOverlayService().endPipSession();
    await service.unsubscribe();
    return super.close();
  }
}

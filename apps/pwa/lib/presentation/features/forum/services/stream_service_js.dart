part of 'stream_service.dart';

// JS interop bindings for window.lynkVideoStreamHelper (web/js/video_stream_helper.js). Kept in
// their own part so the service file is just the service; part files share its private names.

@JS('window.lynkVideoStreamHelper.startVideoStream')
external JSPromise<JSBoolean> _jsStartVideoStream(
    JSString elementId, JSBoolean isFrontCamera);

@JS('window.lynkVideoStreamHelper.toggleCameraEnabled')
external void _jsToggleCameraEnabled(JSBoolean enabled);

@JS('window.lynkVideoStreamHelper.toggleMicEnabled')
external void _jsToggleMicEnabled(JSBoolean enabled);

@JS('window.lynkVideoStreamHelper.requestPictureInPicture')
external JSPromise<JSBoolean> _jsRequestPictureInPicture(JSString elementId);

@JS('window.lynkVideoStreamHelper.startScreenShare')
external JSPromise<JSBoolean> _jsStartScreenShare(JSString elementId);

@JS('window.lynkVideoStreamHelper.stopVideoStream')
external void _jsStopVideoStream();

@JS('window.lynkAudioStreamHelper.getAudioLevel')
external JSNumber _jsGetAudioLevel();

// Per-co-host level from that participant's own pulled-track analyser —
// the page-wide getAudioLevel above only ever reports this viewer's own mic
// or the single remote stream, so it can't say who among a grid of co-hosts
// is speaking.
@JS('window.lynkAudioStreamHelper.getParticipantAudioLevel')
external JSNumber _jsGetParticipantAudioLevel(JSString userId);

@JS('window.lynkVideoStreamHelper.setCameraMirror')
external void _jsSetCameraMirror(JSBoolean isMirrored);

@JS('window.lynkVideoStreamHelper.resumeVideoPlayback')
external void _jsResumeVideoPlayback(JSString elementId);

@JS('window.lynkAudioStreamHelper.requestWakeLock')
external JSPromise<JSAny?> _jsRequestWakeLock();

@JS('window.lynkAudioStreamHelper.releaseWakeLock')
external JSPromise<JSAny?> _jsReleaseWakeLock();

// A video call's co-host audio pull goes through lynkAudioStreamHelper
// directly (same bridging pattern as getAudioLevel/requestWakeLock above),
// not through a separate ForumAudioStreamService instance — audio
// playback for ANY call (audio-only or video) is that JS helper's
// responsibility; ForumVideoStreamService only owns video.
@JS('window.lynkAudioStreamHelper.addParticipantTrack')
external JSPromise<JSBoolean> _jsAddAudioParticipantTrack(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString participantUserId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.removeParticipantTrack')
external void _jsRemoveAudioParticipantTrack(JSString participantUserId);

// Establishes the audio listener connection for a video call — needed
// because lynkVideoStreamHelper's recvonly transceiver is video-only, so
// the host's audio track (published alongside video — see
// publishCloudflareTracks) is pulled through lynkAudioStreamHelper instead.
// addParticipantAudioTrack (co-host audio, above) requires this connection
// to already exist, same as an audio-only call requires its own joinAsListener first.
@JS('window.lynkAudioStreamHelper.joinAsListener')
external JSPromise<JSBoolean> _jsJoinAudioListenerForVideoCall(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkAudioStreamHelper.stopListening')
external void _jsStopListeningAudioForVideoCall();

@JS('window.lynkVideoStreamHelper.publishCloudflareTracks')
external JSPromise<JSBoolean> _jsPublishCloudflareTracks(
  JSString appId,
  JSString sessionId,
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSBoolean forceReconnect,
  JSString trackBaseName,
);

@JS('window.lynkVideoStreamHelper.joinAsVideoListener')
external JSPromise<JSBoolean> _jsJoinAsVideoListener(
  JSString elementId,
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkVideoStreamHelper.stopListeningVideo')
external void _jsStopListeningVideo();

@JS('window.lynkVideoStreamHelper.addParticipantVideoTrack')
external JSPromise<JSBoolean> _jsAddParticipantVideoTrack(
  JSString edgeFunctionUrl,
  JSString authToken,
  JSString forumId,
  JSString participantUserId,
  JSString slotElementId,
  JSString remoteSessionId,
  JSString remoteTrackName,
);

@JS('window.lynkVideoStreamHelper.removeParticipantVideoTrack')
external void _jsRemoveParticipantVideoTrack(JSString participantUserId);

@JS('window.lynkVideoStreamHelper.getTelemetryStats')
external JSPromise<JSString> _jsGetTelemetryStats();

@JS('window.lynkVideoStreamHelper.getListenerTelemetryStats')
external JSPromise<JSString> _jsGetListenerTelemetryStats();

@JS('window.lynkVideoStreamHelper.setStreamQuality')
external JSPromise<JSBoolean> _jsSetStreamQuality(
    JSString elementId, JSString quality);

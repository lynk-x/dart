import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Role of the active user in the audio room session.
enum ForumHeaderRole { host, speaker, listener }

/// Polymorphic Header component for the Forum screen.
///
/// Delegates layout and interactions across dedicated sub-widgets:
/// - [SearchSlot]: Default forum title display and search mode.
/// - [AudioSessionSlot]: Live WebRTC audio call status and volume controls.
/// - [VideoSessionSlot]: Live video broadcast status and host termination controls.
class ForumHeader extends StatelessWidget {
  /// Callback triggered when the user types in the search field.
  final Function(String)? onSearch;

  /// Callback triggered when the search mode is toggled.
  final VoidCallback? onSearchToggle;

  /// When true, user has organizer privileges.
  final bool isOrganizer;

  /// Current read-only state of the forum (true = locked).
  final bool isReadOnly;

  /// Called when the organizer taps the lock/unlock button.
  final VoidCallback? onLockToggle;

  /// The name of the forum to display.
  final String forumName;

  /// Audio / Video live room parameters
  final bool isAudioLive;
  final bool isVideoStreamLive;
  final ForumHeaderRole role;
  final List<String> activeSpeakerNames;
  final String? currentUserName;
  final bool isMicMuted;
  final bool isCameraOn;
  final bool isBroadcastMuted;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleBroadcastMute;
  final VoidCallback? onEndBroadcast;

  /// Callback returning real-time audio amplitude (0.0 to 1.0) from Web Audio AnalyserNode
  final double Function()? getAudioLevel;

  /// Callback triggered when the organizer double taps the left icon to start an audio stream.
  final VoidCallback? onStartAudioStream;

  /// Callback triggered when the organizer long presses the left icon to initialize the live stream UI.
  final VoidCallback? onStartLiveStream;

  const ForumHeader({
    super.key,
    this.onSearch,
    this.onSearchToggle,
    this.isOrganizer = false,
    this.isReadOnly = false,
    this.onLockToggle,
    this.forumName = 'Community Forum',
    this.isAudioLive = false,
    this.isVideoStreamLive = false,
    this.role = ForumHeaderRole.listener,
    this.activeSpeakerNames = const [],
    this.currentUserName,
    this.isMicMuted = true,
    this.isCameraOn = true,
    this.isBroadcastMuted = false,
    this.onToggleMic,
    this.onToggleCamera,
    this.onToggleBroadcastMute,
    this.onEndBroadcast,
    this.getAudioLevel,
    this.onStartAudioStream,
    this.onStartLiveStream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: context.accentColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildHeaderBody(),
    );
  }

  Widget _buildHeaderBody() {
    if (isVideoStreamLive) {
      return VideoSessionSlot(
        role: role,
        isOrganizer: isOrganizer,
        isBroadcastMuted: isBroadcastMuted,
        onToggleBroadcastMute: onToggleBroadcastMute,
        onEndBroadcast: onEndBroadcast,
      );
    } else if (isAudioLive) {
      return AudioSessionSlot(
        role: role,
        activeSpeakerNames: activeSpeakerNames,
        currentUserName: currentUserName,
        isBroadcastMuted: isBroadcastMuted,
        onToggleBroadcastMute: onToggleBroadcastMute,
        onEndBroadcast: onEndBroadcast,
      );
    } else {
      return SearchSlot(
        forumName: forumName,
        onSearch: onSearch,
        onSearchToggle: onSearchToggle,
        onStartAudioStream: onStartAudioStream,
        onStartLiveStream: onStartLiveStream,
      );
    }
  }
}

/// Default slot handling community search input and title display.
class SearchSlot extends StatefulWidget {
  final String forumName;
  final Function(String)? onSearch;
  final VoidCallback? onSearchToggle;
  final VoidCallback? onStartAudioStream;
  final VoidCallback? onStartLiveStream;

  const SearchSlot({
    super.key,
    required this.forumName,
    this.onSearch,
    this.onSearchToggle,
    this.onStartAudioStream,
    this.onStartLiveStream,
  });

  @override
  State<SearchSlot> createState() => _SearchSlotState();
}

class _SearchSlotState extends State<SearchSlot> {
  bool _isSearching = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        GestureDetector(
          onDoubleTap: widget.onStartAudioStream,
          onLongPress: widget.onStartLiveStream,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Icon(_isSearching ? Icons.search : Icons.forum, color: Colors.black),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _isSearching
              ? TextField(
                  autofocus: true,
                  cursorColor: Colors.black,
                  style: AppTypography.interTight(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  onChanged: widget.onSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search community...',
                    hintStyle: TextStyle(color: Colors.black54),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                )
              : Text(
                  widget.forumName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.interTight(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
        ),
        IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.search,
            color: Colors.black,
          ),
          onPressed: () {
            setState(() => _isSearching = !_isSearching);
            widget.onSearchToggle?.call();
          },
        ),
      ],
    );
  }
}

/// Slot displaying live audio call active speakers and volume controls.
class AudioSessionSlot extends StatelessWidget {
  final ForumHeaderRole role;
  final List<String> activeSpeakerNames;
  final String? currentUserName;
  final bool isBroadcastMuted;
  final VoidCallback? onToggleBroadcastMute;
  final VoidCallback? onEndBroadcast;

  const AudioSessionSlot({
    super.key,
    required this.role,
    required this.activeSpeakerNames,
    this.currentUserName,
    this.isBroadcastMuted = false,
    this.onToggleBroadcastMute,
    this.onEndBroadcast,
  });

  String _resolveCenterText() {
    if (activeSpeakerNames.isEmpty) {
      return role == ForumHeaderRole.host ? 'Live Call (Hosting)' : 'Live Call happening';
    }

    final isSelfSpeaking = currentUserName != null && activeSpeakerNames.contains(currentUserName);
    final otherSpeakers = currentUserName != null
        ? activeSpeakerNames.where((name) => name != currentUserName).toList()
        : activeSpeakerNames;

    if (isSelfSpeaking) {
      if (otherSpeakers.isEmpty) return 'You (Speaking)';
      return 'You + ${otherSpeakers.length} other${otherSpeakers.length > 1 ? "s" : ""} (Speaking)';
    }

    if (activeSpeakerNames.length == 1) return '${activeSpeakerNames[0]} (Speaking)';
    if (activeSpeakerNames.length == 2) return '${activeSpeakerNames[0]} + ${activeSpeakerNames[1]} (Speaking)';

    return '${activeSpeakerNames[0]} + ${activeSpeakerNames.length - 1} others (Speaking)';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.0),
          child: Icon(Icons.graphic_eq_rounded, color: Colors.black, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _resolveCenterText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.interTight(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        if (role == ForumHeaderRole.host)
          IconButton(
            icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
            onPressed: onEndBroadcast,
            tooltip: 'End Broadcast',
          )
        else
          IconButton(
            icon: Icon(
              isBroadcastMuted ? Icons.volume_off : Icons.volume_up,
              color: isBroadcastMuted ? Colors.red : Colors.black,
            ),
            onPressed: onToggleBroadcastMute,
            tooltip: isBroadcastMuted ? 'Unmute Broadcast' : 'Mute Broadcast',
          ),
      ],
    );
  }
}

/// Slot displaying live video broadcast status and host termination controls.
class VideoSessionSlot extends StatelessWidget {
  final ForumHeaderRole role;
  final bool isOrganizer;
  final bool isBroadcastMuted;
  final VoidCallback? onToggleBroadcastMute;
  final VoidCallback? onEndBroadcast;

  const VideoSessionSlot({
    super.key,
    required this.role,
    this.isOrganizer = false,
    this.isBroadcastMuted = false,
    this.onToggleBroadcastMute,
    this.onEndBroadcast,
  });

  @override
  Widget build(BuildContext context) {
    final isHostOrOrganizer = role == ForumHeaderRole.host || isOrganizer;

    return Row(
      children: [
        const SizedBox(width: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.0),
          child: Icon(Icons.videocam_rounded, color: Colors.black, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Live Stream happening',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.interTight(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        if (isHostOrOrganizer)
          IconButton(
            icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
            onPressed: onEndBroadcast,
            tooltip: 'End Live Stream',
          )
        else
          IconButton(
            icon: Icon(
              isBroadcastMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: isBroadcastMuted ? Colors.red : Colors.black,
            ),
            onPressed: onToggleBroadcastMute,
            tooltip: isBroadcastMuted ? 'Unmute Stream Audio' : 'Mute Stream Audio',
          ),
      ],
    );
  }
}

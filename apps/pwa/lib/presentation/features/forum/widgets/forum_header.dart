import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Role of the active user in the audio room session.
enum ForumHeaderRole { host, speaker, listener }

/// Polymorphic Header component for the Forum screen.
///
/// Adapts between standard forum search mode and live audio room state
/// with a fixed [Left Icon] - [Center Text] - [Right Icon] layout.
class ForumHeader extends StatefulWidget {
  /// Callback triggered when the user types in the search field.
  final Function(String)? onSearch;

  /// Callback triggered when the search mode is toggled.
  final VoidCallback? onSearchToggle;

  /// When true, the lock/unlock icon button is shown.
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
  State<ForumHeader> createState() => _ForumHeaderState();
}

class _ForumHeaderState extends State<ForumHeader> {
  bool _isSearching = false;

  String _resolveCenterText() {
    if (widget.isVideoStreamLive) return 'Live Stream happening';
    if (!widget.isAudioLive) return widget.forumName;

    final speakers = widget.activeSpeakerNames;
    if (speakers.isEmpty) return widget.forumName;

    final isSelfSpeaking = widget.currentUserName != null && speakers.contains(widget.currentUserName);
    final otherSpeakers = widget.currentUserName != null
        ? speakers.where((name) => name != widget.currentUserName).toList()
        : speakers;

    if (isSelfSpeaking) {
      if (otherSpeakers.isEmpty) return 'You (Speaking)';
      return 'You + ${otherSpeakers.length} other${otherSpeakers.length > 1 ? "s" : ""} (Speaking)';
    }

    if (speakers.length == 1) return '${speakers[0]} (Speaking)';
    if (speakers.length == 2) return '${speakers[0]} + ${speakers[1]} (Speaking)';

    return '${speakers[0]} + ${speakers.length - 1} others (Speaking)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: context.accentColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),

          // SLOT 1: Left Icon (Dual Mic & Camera Toggle buttons during live stream)
          if (widget.isVideoStreamLive)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // MIC TOGGLE BUTTON
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    widget.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: widget.isMicMuted ? Colors.red : Colors.black,
                    size: 20,
                  ),
                  onPressed: widget.onToggleMic,
                  tooltip: widget.isMicMuted ? 'Unmute Mic' : 'Mute Mic',
                ),

                // CAMERA TOGGLE BUTTON
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    widget.isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    color: widget.isCameraOn ? Colors.black : Colors.red,
                    size: 20,
                  ),
                  onPressed: widget.onToggleCamera,
                  tooltip: widget.isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
                ),
              ],
            )
          else if (widget.isAudioLive && (widget.role == ForumHeaderRole.host || widget.role == ForumHeaderRole.speaker))
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                widget.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: widget.isMicMuted ? Colors.red : Colors.black,
                size: 20,
              ),
              onPressed: widget.onToggleMic,
              tooltip: widget.isMicMuted ? 'Unmute Mic' : 'Mute Mic',
            )
          else if (widget.isAudioLive)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(Icons.volume_up_rounded, color: Colors.black, size: 20),
            )
          else
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

          // SLOT 2: Center Text ("Live Stream happening" / Forum Name / Active Speakers)
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

          // SLOT 3: Right Icon (Audio Mute Toggle / End Broadcast / Search Toggle)
          if (widget.isVideoStreamLive && (widget.role == ForumHeaderRole.host || widget.isOrganizer))
            IconButton(
              icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
              onPressed: widget.onEndBroadcast,
              tooltip: 'End Live Stream',
            )
          else if (widget.isVideoStreamLive)
            IconButton(
              icon: Icon(
                widget.isBroadcastMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: widget.isBroadcastMuted ? Colors.red : Colors.black,
              ),
              onPressed: widget.onToggleBroadcastMute,
              tooltip: widget.isBroadcastMuted ? 'Unmute Stream Audio' : 'Mute Stream Audio',
            )
          else if (widget.isAudioLive && widget.role == ForumHeaderRole.host)
            IconButton(
              icon: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
              onPressed: widget.onEndBroadcast,
              tooltip: 'End Broadcast',
            )
          else if (widget.isAudioLive)
            IconButton(
              icon: Icon(
                widget.isBroadcastMuted ? Icons.volume_off : Icons.volume_up,
                color: widget.isBroadcastMuted ? Colors.red : Colors.black,
              ),
              onPressed: widget.onToggleBroadcastMute,
              tooltip: widget.isBroadcastMuted ? 'Unmute Broadcast' : 'Mute Broadcast',
            )
          else
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
      ),
    );
  }
}

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

  /// Audio room parameters
  final bool isAudioLive;
  final ForumHeaderRole role;
  final List<String> activeSpeakerNames;
  final String? currentUserName;
  final bool isMicMuted;
  final bool isBroadcastMuted;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleBroadcastMute;
  final VoidCallback? onEndBroadcast;

  /// Callback triggered when the organizer long presses the left icon to start an audio stream.
  final VoidCallback? onStartAudioStream;

  const ForumHeader({
    super.key,
    this.onSearch,
    this.onSearchToggle,
    this.isOrganizer = false,
    this.isReadOnly = false,
    this.onLockToggle,
    this.forumName = 'Community Forum',
    this.isAudioLive = false,
    this.role = ForumHeaderRole.listener,
    this.activeSpeakerNames = const [],
    this.currentUserName,
    this.isMicMuted = true,
    this.isBroadcastMuted = false,
    this.onToggleMic,
    this.onToggleBroadcastMute,
    this.onEndBroadcast,
    this.onStartAudioStream,
  });

  @override
  State<ForumHeader> createState() => _ForumHeaderState();
}

class _ForumHeaderState extends State<ForumHeader> {
  bool _isSearching = false;

  String _resolveCenterText() {
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
    final isSpeaking = widget.activeSpeakerNames.isNotEmpty;

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

          // SLOT 1: Left Icon (Long press to start audio stream for organizer)
          if (widget.isAudioLive && (widget.role == ForumHeaderRole.host || widget.role == ForumHeaderRole.speaker))
            IconButton(
              icon: Icon(
                widget.isMicMuted ? Icons.mic_off : Icons.mic,
                color: widget.isMicMuted ? Colors.red : Colors.black,
              ),
              onPressed: widget.onToggleMic,
              tooltip: widget.isMicMuted ? 'Unmute Mic' : 'Mute Mic',
            )
          else if (widget.isAudioLive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: AnimatedSoundwaveWidget(isSpeaking: isSpeaking),
            )
          else
            GestureDetector(
              onDoubleTap: widget.isOrganizer ? widget.onStartAudioStream : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(_isSearching ? Icons.search : Icons.forum, color: Colors.black),
              ),
            ),

          const SizedBox(width: 8),

          // SLOT 2: Center Text
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

          // SLOT 3: Right Icon
          if (widget.isAudioLive && widget.role == ForumHeaderRole.host)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
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

/// Animated Soundwave Widget for Flutter PWA listeners
class AnimatedSoundwaveWidget extends StatelessWidget {
  final bool isSpeaking;

  const AnimatedSoundwaveWidget({super.key, required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Bar(isSpeaking: isSpeaking, height: 14),
          _Bar(isSpeaking: isSpeaking, height: 18),
          _Bar(isSpeaking: isSpeaking, height: 10),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final bool isSpeaking;
  final double height;

  const _Bar({required this.isSpeaking, required this.height});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 3,
      height: isSpeaking ? height : 4,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

import 'dart:async';
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
    this.role = ForumHeaderRole.listener,
    this.activeSpeakerNames = const [],
    this.currentUserName,
    this.isMicMuted = true,
    this.isBroadcastMuted = false,
    this.onToggleMic,
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

          // SLOT 1: Left Icon (Mic toggle / start audio stream on double tap / start live stream on long press)
          if (widget.isAudioLive && (widget.role == ForumHeaderRole.host || widget.role == ForumHeaderRole.speaker))
            widget.isMicMuted
                ? IconButton(
                    icon: const Icon(Icons.mic_off_rounded, color: Colors.red),
                    onPressed: widget.onToggleMic,
                    tooltip: 'Unmute Mic',
                  )
                : _ActiveMicWaveButton(
                    onToggleMic: widget.onToggleMic,
                    getAudioLevel: widget.getAudioLevel,
                  )
          else if (widget.isAudioLive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: AnimatedSoundwaveWidget(
                isSpeaking: isSpeaking,
                getAudioLevel: widget.getAudioLevel,
              ),
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

/// Animated Soundwave Widget for Flutter PWA listeners
class AnimatedSoundwaveWidget extends StatefulWidget {
  final bool isSpeaking;
  final double Function()? getAudioLevel;

  const AnimatedSoundwaveWidget({
    super.key,
    required this.isSpeaking,
    this.getAudioLevel,
  });

  @override
  State<AnimatedSoundwaveWidget> createState() => _AnimatedSoundwaveWidgetState();
}

class _AnimatedSoundwaveWidgetState extends State<AnimatedSoundwaveWidget> {
  Timer? _levelTimer;
  double _currentLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _levelTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      final raw = widget.getAudioLevel?.call() ?? 0.0;
      if ((raw - _currentLevel).abs() > 0.01) {
        setState(() {
          _currentLevel = (_currentLevel * 0.3) + (raw * 0.7);
        });
      }
    });
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isSpeaking;
    final lvl = active ? (_currentLevel > 0.04 ? _currentLevel : 0.25) : 0.0;

    return SizedBox(
      width: 20,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Bar(height: active ? 6.0 + (lvl * 10.0) : 4.0),
          _Bar(height: active ? 8.0 + (lvl * 12.0) : 4.0),
          _Bar(height: active ? 5.0 + (lvl * 8.0) : 4.0),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;

  const _Bar({required this.height});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: 3,
      height: height.clamp(4.0, 18.0),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Interactive Microphone button displaying a real-time vocal amplitude wave animation when active.
class _ActiveMicWaveButton extends StatefulWidget {
  final VoidCallback? onToggleMic;
  final double Function()? getAudioLevel;

  const _ActiveMicWaveButton({
    required this.onToggleMic,
    this.getAudioLevel,
  });

  @override
  State<_ActiveMicWaveButton> createState() => _ActiveMicWaveButtonState();
}

class _ActiveMicWaveButtonState extends State<_ActiveMicWaveButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _idleController;
  Timer? _levelTimer;
  double _currentLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startLevelPolling();
  }

  void _startLevelPolling() {
    _levelTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final rawLevel = widget.getAudioLevel?.call() ?? 0.0;
      final smoothed = (_currentLevel * 0.3) + (rawLevel * 0.7);
      if ((smoothed - _currentLevel).abs() > 0.005) {
        setState(() {
          _currentLevel = smoothed;
        });
      }
    });
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onToggleMic,
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: 'Mute Mic',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mic_rounded,
                color: Colors.black,
                size: 20,
              ),
              const SizedBox(width: 4),
              AnimatedBuilder(
                animation: _idleController,
                builder: (context, child) {
                  final idleVal = _idleController.value;
                  final isSpeaking = _currentLevel > 0.03;

                  final h1 = isSpeaking
                      ? (6.0 + (_currentLevel * 14.0))
                      : (4.0 + (3.0 * idleVal));
                  final h2 = isSpeaking
                      ? (8.0 + (_currentLevel * 18.0))
                      : (5.0 + (4.0 * (1.0 - idleVal)));
                  final h3 = isSpeaking
                      ? (5.0 + (_currentLevel * 12.0))
                      : (4.0 + (3.0 * idleVal));

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WaveBar(height: h1),
                      const SizedBox(width: 2.5),
                      _WaveBar(height: h2),
                      const SizedBox(width: 2.5),
                      _WaveBar(height: h3),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveBar extends StatelessWidget {
  final double height;

  const _WaveBar({required this.height});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      width: 2.5,
      height: height.clamp(4.0, 20.0),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

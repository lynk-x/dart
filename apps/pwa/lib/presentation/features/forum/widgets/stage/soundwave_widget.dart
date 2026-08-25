import 'package:flutter/material.dart';

/// Dynamic soundwave visualizer widget driven by a [ValueNotifier<double>] audio level.
///
/// Replaces the previous Timer-based polling with a lightweight notifier listener,
/// so the widget only rebuilds when the audio level actually changes —
/// not on a fixed 50ms tick regardless of data freshness.
///
/// Smoothing is applied via exponential moving average
/// (α=0.7 toward raw) on each notifier change, preventing jitter.
class SoundwaveWidget extends StatefulWidget {
  /// Shared audio-level notifier. Expected range: 0.0–1.0.
  final ValueNotifier<double> audioLevelNotifier;

  /// When false the bars immediately collapse to resting state (4px).
  final bool isSpeaking;

  final Color barColor;

  const SoundwaveWidget({
    super.key,
    required this.audioLevelNotifier,
    required this.isSpeaking,
    this.barColor = Colors.white,
  });

  @override
  State<SoundwaveWidget> createState() => _SoundwaveWidgetState();
}

class _SoundwaveWidgetState extends State<SoundwaveWidget> {
  double _smoothedLevel = 0.0;

  @override
  void initState() {
    super.initState();
    widget.audioLevelNotifier.addListener(_onLevelChanged);
  }

  @override
  void didUpdateWidget(SoundwaveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioLevelNotifier != widget.audioLevelNotifier) {
      oldWidget.audioLevelNotifier.removeListener(_onLevelChanged);
      widget.audioLevelNotifier.addListener(_onLevelChanged);
    }
  }

  /// Called whenever the audio level notifier pushes a new value.
  /// Applies exponential moving average (α=0.7 toward raw) for smooth response.
  void _onLevelChanged() {
    if (!mounted) return;
    if (!widget.isSpeaking) {
      if (_smoothedLevel != 0.0) setState(() => _smoothedLevel = 0.0);
      return;
    }
    final raw = widget.audioLevelNotifier.value;
    final smoothed = (_smoothedLevel * 0.3) + (raw * 0.7);
    if ((smoothed - _smoothedLevel).abs() > 0.005) {
      setState(() => _smoothedLevel = smoothed);
    }
  }

  @override
  void dispose() {
    widget.audioLevelNotifier.removeListener(_onLevelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isSpeaking && _smoothedLevel > 0.03;
    final lvl = active ? _smoothedLevel.clamp(0.0, 1.0) : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Bar(
          height: active ? (5.0 + (lvl * 9.0)).clamp(4.0, 14.0) : 4.0,
          color: active ? widget.barColor : Colors.white24,
        ),
        _Bar(
          height: active ? (7.0 + (lvl * 12.0)).clamp(4.0, 18.0) : 4.0,
          color: active ? widget.barColor : Colors.white24,
        ),
        _Bar(
          height: active ? (4.5 + (lvl * 8.0)).clamp(4.0, 13.0) : 4.0,
          color: active ? widget.barColor : Colors.white24,
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;

  const _Bar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';

/// Animated soundwave visualizer widget indicating active mic speaking level.
class AnimatedSoundwaveWidget extends StatefulWidget {
  final bool isSpeaking;
  final double Function() getAudioLevel;
  final Color barColor;

  const AnimatedSoundwaveWidget({
    super.key,
    required this.isSpeaking,
    required this.getAudioLevel,
    this.barColor = Colors.white,
  });

  @override
  State<AnimatedSoundwaveWidget> createState() => _AnimatedSoundwaveWidgetState();
}

class _AnimatedSoundwaveWidgetState extends State<AnimatedSoundwaveWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpeaking) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 2.5,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final rawLevel = widget.getAudioLevel();
        final level = rawLevel > 0 ? rawLevel : 0.4;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final h = (6.0 + (sin((_anim.value * 2 * pi) + i) * 6 * level)).clamp(4.0, 14.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 2.5,
              height: h,
              decoration: BoxDecoration(
                color: widget.barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

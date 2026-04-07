import 'package:flutter/material.dart';
import 'dart:math';

// Helper class to hold all data for a single animation.
class _AnimationData {
  final UniqueKey key;
  final AnimationController controller;
  final Animation<double> yPosition;
  final Animation<double> opacity;
  final double xPosition;
  final String emoji;

  _AnimationData({
    required this.key,
    required this.controller,
    required this.yPosition,
    required this.opacity,
    required this.xPosition,
    required this.emoji,
  });
}

class ReactionBackground extends StatefulWidget {
  const ReactionBackground({
    super.key,
    this.width,
    this.height,
    required this.emoji,
    required this.trigger,
  });

  final double? width;
  final double? height;
  final String emoji;
  final int trigger;

  @override
  State<ReactionBackground> createState() => _ReactionBackgroundState();
}

class _ReactionBackgroundState extends State<ReactionBackground>
    with TickerProviderStateMixin {
  final List<_AnimationData> _animations = [];
  final Random _random = Random();
  BoxConstraints? _constraints;

  // --- PERFORMANCE OPTIMIZATION ---
  static const int _throttleMilliseconds = 200;
  int _lastTriggerTime = 0;
  static const int _maxAnimations = 30;
  // --- END OF OPTIMIZATION VARIABLES ---

  @override
  void didUpdateWidget(covariant ReactionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger &&
        widget.emoji.isNotEmpty &&
        _constraints != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastTriggerTime > _throttleMilliseconds) {
        _lastTriggerTime = now;
        _startAnimation();
      }
    }
  }

  void _startAnimation() {
    if (_constraints == null) return;

    if (_animations.length >= _maxAnimations) {
      final oldest = _animations.first;
      oldest.controller.dispose();
      _animations.removeAt(0);
    }

    final controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    final animationWidth = _constraints!.maxWidth;
    final animationHeight = _constraints!.maxHeight;

    if (animationWidth <= 0 || animationHeight <= 0) {
      controller.dispose();
      return;
    }

    final randomX = _random.nextDouble() * (animationWidth - 40.0);
    final yPositionAnimation =
        Tween<double>(begin: 0.0, end: animationHeight).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );
    final opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: controller, curve: const Interval(0.4, 1.0)),
    );

    final animationData = _AnimationData(
      key: UniqueKey(),
      controller: controller,
      yPosition: yPositionAnimation,
      opacity: opacityAnimation,
      xPosition: randomX,
      emoji: widget.emoji,
    );

    setState(() {
      _animations.add(animationData);
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _animations
                .removeWhere((element) => element.key == animationData.key);
          });
        }
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  void dispose() {
    for (var animation in _animations) {
      animation.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _constraints = constraints;

        return IgnorePointer(
          child: ClipRect(
            child: Stack(
              children: _animations.map((data) {
                return AnimatedBuilder(
                  animation: data.controller,
                  builder: (context, child) {
                    return Positioned(
                      left: data.xPosition,
                      bottom: data.yPosition.value,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Opacity(
                          opacity: data.opacity.value,
                          child: Text(
                            data.emoji,
                            style: const TextStyle(
                                fontSize: 40, decoration: TextDecoration.none),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

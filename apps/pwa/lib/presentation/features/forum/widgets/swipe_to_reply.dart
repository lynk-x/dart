import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lynk_core/core.dart';

/// A wrapper widget that allows swiping left on a chat bubble to trigger a reply.
///
/// Features elastic damping, tactile haptic feedback on activation,
/// and smooth back-springing animation.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragOffset = 0.0;
  bool _hasTriggeredHaptic = false;
  VoidCallback? _activeSpringListener;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    const maxDrag = 60.0;
    const threshold = 40.0;
    final progress = (_dragOffset.abs() / maxDrag).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        setState(() {
          // Allow swiping left (negative drag offset)
          _dragOffset += details.primaryDelta! * 0.6;
          _dragOffset = _dragOffset.clamp(-maxDrag, 0.0);

          if (_dragOffset.abs() >= threshold && !_hasTriggeredHaptic) {
            HapticFeedback.lightImpact();
            _hasTriggeredHaptic = true;
          } else if (_dragOffset.abs() < threshold) {
            _hasTriggeredHaptic = false;
          }
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() >= threshold) {
          widget.onReply();
        }

        _controller.forward(from: 0.0);
        final start = _dragOffset;
        if (_activeSpringListener != null) {
          _controller.removeListener(_activeSpringListener!);
        }
        _activeSpringListener = _onSpringAnimationUpdate(start);
        _controller.addListener(_activeSpringListener!);
        _hasTriggeredHaptic = false;
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          // Pinned/Centered reply icon container on the right side
          Positioned(
            right: 8,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + (progress * 0.4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply,
                    color: context.accentColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          // Foregound slide-translated content
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  VoidCallback _onSpringAnimationUpdate(double start) {
    return () {
      if (!mounted) return;
      setState(() {
        _dragOffset = Tween<double>(begin: start, end: 0.0)
            .animate(CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOutBack,
            ))
            .value;
      });
    };
  }

  @override
  void dispose() {
    if (_activeSpringListener != null) {
      _controller.removeListener(_activeSpringListener!);
    }
    _controller.dispose();
    super.dispose();
  }
}

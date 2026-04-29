import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lynk_core/core.dart';

class WelcomeBanner extends StatelessWidget {
  final bool show;
  final VoidCallback onDismiss;

  const WelcomeBanner({
    super.key,
    required this.show,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF20F928).withValues(alpha: 0.15),
              Colors.transparent
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: const Color(0xFF20F928).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF20F928),
              child: Icon(Icons.celebration, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to the Community!',
                    style: AppTypography.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  Text(
                    'Introduce yourself in the Live Chat or see the latest updates.',
                    style:
                        AppTypography.inter(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white24, size: 18),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.1);
  }
}

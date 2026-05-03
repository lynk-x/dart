import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PodiumScreen extends StatelessWidget {
  final List<Map<String, dynamic>> winners;
  final int finalScore;
  final VoidCallback onExit;
  final bool isHost;

  const PodiumScreen({
    super.key,
    required this.winners,
    required this.finalScore,
    required this.onExit,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              
              // Header
              Text(
                "FINAL PODIUM",
                style: AppTypography.labelLarge.copyWith(
                  color: const Color(0xFFFFD700), // Gold
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fadeIn().scale(),
              
              const SizedBox(height: 40),
              
              // Winners List
              Expanded(
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: winners.length > 3 ? 3 : winners.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final winner = winners[index];
                    return _PodiumItem(
                      rank: index + 1,
                      name: winner['display_name'] ?? 'Player',
                      score: winner['total_score'] ?? 0,
                    ).animate()
                     .fadeIn(delay: (index * 200).ms)
                     .slideY(begin: 0.2, end: 0);
                  },
                ),
              ),
              
              // Personal Final Score
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Text(
                      "YOUR FINAL SCORE",
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.alternate,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "$finalScore",
                      style: AppTypography.h1.copyWith(
                        color: const Color(0xFFFFD700),
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .shimmer(duration: 2.seconds, color: Colors.white24),
                  ],
                ),
              ),
              
              // Exit Button
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: onExit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isHost ? "CLOSE QUIZ" : "BACK TO FORUM",
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 800.ms),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final int rank;
  final String name;
  final int score;

  const _PodiumItem({
    required this.rank,
    required this.name,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFirst = rank == 1;
    final Color rankColor = isFirst ? const Color(0xFFFFD700) : context.accentColor;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isFirst ? rankColor.withValues(alpha: 0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFirst ? rankColor : Colors.white10,
          width: isFirst ? 2 : 1,
        ),
        boxShadow: isFirst ? [
          BoxShadow(
            color: rankColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ] : null,
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              isFirst ? "👑" : "#$rank",
              style: TextStyle(
                fontSize: isFirst ? 24 : 18,
                fontWeight: FontWeight.bold,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.bodyLarge.copyWith(
                    color: Colors.white,
                    fontWeight: isFirst ? FontWeight.w900 : FontWeight.w700,
                    fontSize: isFirst ? 20 : 16,
                  ),
                ),
                Text(
                  "$score Points",
                  style: AppTypography.bodyMedium.copyWith(
                    color: rankColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

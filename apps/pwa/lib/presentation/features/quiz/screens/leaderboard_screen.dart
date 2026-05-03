import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_animate/flutter_animate.dart';

class LeaderboardScreen extends StatelessWidget {
  final List<Map<String, dynamic>> leaderboard;
  final int userScore;
  final int? userRank;
  final bool isLoading;
  final bool isHost;
  final VoidCallback? onNext;
  final bool isLastQuestion;

  const LeaderboardScreen({
    super.key,
    required this.leaderboard,
    required this.userScore,
    this.userRank,
    this.isLoading = false,
    this.isHost = false,
    this.onNext,
    this.isLastQuestion = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                "STANDINGS",
                style: AppTypography.labelLarge.copyWith(
                  color: context.accentColor,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fadeIn().moveY(begin: -10, end: 0),
              
              const SizedBox(height: 8),
              
              Text(
                "Global Standings",
                style: AppTypography.h1.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ).animate().fadeIn(delay: 100.ms),
              
              const SizedBox(height: 40),
              
              // Leaderboard List
              Expanded(
                child: isLoading 
                  ? Center(child: CircularProgressIndicator(color: context.accentColor))
                  : leaderboard.isEmpty
                    ? Center(
                        child: Text(
                          "Calculating scores...",
                          style: AppTypography.bodyLarge.copyWith(color: AppColors.alternate),
                        ),
                      )
                    : ListView.separated(
                        itemCount: leaderboard.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = leaderboard[index];
                          final isUser = entry['is_current_user'] == true;
                          
                          return _LeaderboardItem(
                            rank: index + 1,
                            name: entry['display_name'] ?? 'Player',
                            score: entry['total_score'] ?? 0,
                            isUser: isUser,
                          ).animate()
                           .fadeIn(delay: (index * 100).ms)
                           .slideX(begin: 0.1, end: 0);
                        },
                      ),
              ),
              
              const SizedBox(height: 40),
              
              // User Personal Stats
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: "YOUR RANK",
                      value: userRank != null ? "#$userRank" : "--",
                      color: context.accentColor,
                    ),
                    Container(width: 1, height: 40, color: AppColors.outline),
                    _StatItem(
                      label: "TOTAL SCORE",
                      value: "$userScore",
                      color: context.accentColor,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),
              
              const SizedBox(height: 32),
              
              if (isHost)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: onNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isLastQuestion ? "FINISH QUIZ" : "NEXT QUESTION",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Text(
                  "Waiting for the host to continue...",
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.alternate.withValues(alpha: 0.5),
                  ),
                ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                 .fadeIn(duration: 1000.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardItem extends StatelessWidget {
  final int rank;
  final String name;
  final int score;
  final bool isUser;

  const _LeaderboardItem({
    required this.rank,
    required this.name,
    required this.score,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isUser ? context.accentColor.withValues(alpha: 0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUser ? context.accentColor : AppColors.outline,
          width: isUser ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              "#$rank",
              style: AppTypography.bodyMedium.copyWith(
                color: isUser ? context.accentColor : AppColors.alternate,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: AppTypography.bodyLarge.copyWith(
                color: Colors.white,
                fontWeight: isUser ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            "$score",
            style: AppTypography.bodyLarge.copyWith(
              color: context.accentColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.alternate,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.h2.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

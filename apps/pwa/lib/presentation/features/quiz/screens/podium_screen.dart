import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';

/// Delay before revealing the podium entry that is [placesFromLast] steps
/// before the winner (0 = the lowest-ranked of the three, increasing toward
/// 1st place). Gaps widen as the winner approaches — 3rd place gets a beat
/// of suspense, 2nd place waits longer still, and 1st place lands at the
/// 4.3s mark (within the requested 4.3-4.5s window) for maximum suspense.
const List<Duration> _podiumRevealGaps = [
  Duration(milliseconds: 1500),
  Duration(milliseconds: 2900),
  Duration(milliseconds: 4300),
];

Duration _podiumRevealDelay(int placesFromLast) {
  if (placesFromLast < 0) return Duration.zero;
  if (placesFromLast >= _podiumRevealGaps.length) return _podiumRevealGaps.last;
  return _podiumRevealGaps[placesFromLast];
}

const Duration _podiumRevealCompleteDelay = Duration(milliseconds: 6000);

class PodiumScreen extends StatefulWidget {
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
  State<PodiumScreen> createState() => _PodiumScreenState();
}

class _PodiumScreenState extends State<PodiumScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Starts as soon as the podium mounts, running alongside the full
    // 6-second reveal sequence (3rd -> 2nd -> 1st).
    _audioPlayer.play(AssetSource('audio/liveQuiz_podium_sound.mp3'));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

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
              
              // Winners List — laid out 1st-on-top as usual, but revealed in
              // the opposite order (3rd, then 2nd, then 1st) with a longer
              // pause before each step, so suspense builds toward the winner
              // instead of the winner appearing first and the tension
              // deflating from there.
              Expanded(
                child: ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.winners.length > 3 ? 3 : widget.winners.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final winner = widget.winners[index];
                    final placesFromLast =
                        (widget.winners.length > 3 ? 3 : widget.winners.length) - 1 - index;
                    final revealDelay = _podiumRevealDelay(placesFromLast);

                    return _PodiumItem(
                      rank: index + 1,
                      name: winner['display_name'] ?? 'Player',
                      score: winner['total_score'] ?? 0,
                    ).animate()
                     .fadeIn(delay: revealDelay, duration: 500.ms)
                     .slideY(begin: 0.2, end: 0, duration: 500.ms);
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
                      "${widget.finalScore}",
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
                      onPressed: widget.onExit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        widget.isHost ? "CLOSE QUIZ" : "BACK TO FORUM",
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: _podiumRevealCompleteDelay),
              
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

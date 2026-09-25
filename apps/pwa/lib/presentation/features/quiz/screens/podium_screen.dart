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
  final bool skipReveal;

  const PodiumScreen({
    super.key,
    required this.winners,
    required this.finalScore,
    required this.onExit,
    this.isHost = false,
    this.skipReveal = false,
  });

  List<Map<String, dynamic>> get _effectiveWinners {
    if (winners.isEmpty) {
      return const [
        {'display_name': '---', 'total_score': 0},
        {'display_name': '---', 'total_score': 0},
        {'display_name': '---', 'total_score': 0},
      ];
    }

    final result = List<Map<String, dynamic>>.from(winners);
    while (result.length < 3) {
      result.add(const {'display_name': '---', 'total_score': 0});
    }
    return result.take(3).toList();
  }

  @override
  State<PodiumScreen> createState() => _PodiumScreenState();
}

class _PodiumScreenState extends State<PodiumScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    if (!widget.skipReveal) {
      _audioPlayer.play(AssetSource('audio/liveQuiz_podium_sound.mp3'));
    }
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 600;
                    final scale = isDesktop ? 1.3 : 1.0;

                    final secondWidth = 80.0 * scale;
                    final firstWidth = 100.0 * scale;
                    final thirdWidth = 80.0 * scale;

                    final secondHeight = 120.0 * scale;
                    final firstHeight = 160.0 * scale;
                    final thirdHeight = 80.0 * scale;

                    final gap = isDesktop ? 24.0 : 12.0;

                    final winners = widget._effectiveWinners;
                    final second = winners[1];
                    final first = winners[0];
                    final third = winners[2];

                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                             _PodiumSlot(
                               rank: 3,
                               name: third['display_name'] ?? '---',
                               score: third['total_score'] ?? 0,
                               podiumWidth: thirdWidth,
                               podiumHeight: thirdHeight,
                             ).animate().fadeIn(delay: _podiumRevealDelay(0), duration: 500.ms).slideY(begin: 0.2, end: 0, duration: 500.ms),
                             SizedBox(width: gap),
                             _PodiumSlot(
                               rank: 2,
                               name: second['display_name'] ?? '---',
                               score: second['total_score'] ?? 0,
                               podiumWidth: secondWidth,
                               podiumHeight: secondHeight,
                             ).animate().fadeIn(delay: _podiumRevealDelay(1), duration: 500.ms).slideY(begin: 0.2, end: 0, duration: 500.ms),
                             SizedBox(width: gap),
                             _PodiumSlot(
                               rank: 1,
                               name: first['display_name'] ?? '---',
                               score: first['total_score'] ?? 0,
                               podiumWidth: firstWidth,
                               podiumHeight: firstHeight,
                             ).animate().fadeIn(delay: _podiumRevealDelay(2), duration: 500.ms).slideY(begin: 0.2, end: 0, duration: 500.ms),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Personal final score
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
                        
                        // Exit button
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
                                  widget.isHost && !widget.skipReveal ? "CLOSE QUIZ" : "BACK TO FORUM",
                                  style: AppTypography.labelLarge.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: widget.skipReveal ? Duration.zero : _podiumRevealCompleteDelay),
                        
                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final int rank;
  final String name;
  final int score;
  final double podiumWidth;
  final double podiumHeight;

  const _PodiumSlot({
    required this.rank,
    required this.name,
    required this.score,
    required this.podiumWidth,
    required this.podiumHeight,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
         // Name (above podium)
         Tooltip(
           message: name,
           child: Text(
             name,
             style: AppTypography.bodyLarge.copyWith(
               color: Colors.white,
               fontWeight: rank == 1 ? FontWeight.w900 : FontWeight.w700,
               fontSize: rank == 1 ? 18 : 14,
             ),
             textAlign: TextAlign.center,
           ),
         ),
        const SizedBox(height: 8),

        // Podium block with rank on it
        Container(
          width: podiumWidth,
          height: podiumHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                rankColor.withValues(alpha: 0.2),
                rankColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: rankColor.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: rankColor.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              rank == 1 ? '👑' : '#$rank',
              style: TextStyle(
                fontSize: podiumWidth * 0.4,
                fontWeight: FontWeight.bold,
                color: rankColor,
              ),
            ),
          ),
        ),

        // Score (below podium)
        const SizedBox(height: 8),
        Text(
          '$score',
          style: AppTypography.bodyMedium.copyWith(
            color: rankColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

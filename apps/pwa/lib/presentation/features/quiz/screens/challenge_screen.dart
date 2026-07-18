import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChallengeScreen extends StatefulWidget {
  final Map<String, dynamic> question;
  final int timeLeft;
  final int? selectedIndex;
  final Function(int) onOptionSelected;
  final bool isHost;
  final VoidCallback? onPause;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  // Reveal support: null until the backend exposes which option(s) were
  // correct (api.v1_questions only populates this once quiz_state moves
  // past 'playing' — see QuizRepository's doc comment). When null, no
  // answer renders correct/wrong styling.
  final List<int>? correctOptionIndices;

  const ChallengeScreen({
    super.key,
    required this.question,
    required this.timeLeft,
    this.selectedIndex,
    required this.onOptionSelected,
    this.isHost = false,
    this.onPause,
    this.onNext,
    this.onBack,
    this.correctOptionIndices,
  });

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  @override
  Widget build(BuildContext context) {
    final options = widget.question['options'] is List
        ? widget.question['options'] as List
        : [];

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: RepaintBoundary(
          child: SvgPicture.asset(
            'assets/images/official_lynk-x_combined-logo.svg',
            width: 140,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: const [SizedBox(width: 48)],
      ),
      bottomNavigationBar: widget.isHost ? _buildHostControls() : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // Question Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.outline)),
              ),
              child: Column(
                children: [
                  // Timer
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: context.accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: context.accentColor.withValues(alpha: 0.3),
                          blurRadius: 15,
                        )
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.timeLeft}',
                      style: AppTypography.h1.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ).animate(target: widget.timeLeft < 5 ? 1 : 0)
                   .shake(hz: 4, curve: Curves.easeInOut),

                  const SizedBox(height: 20),

                  Text(
                    widget.question['question_text'] ?? '',
                    textAlign: TextAlign.center,
                    style: AppTypography.h2.copyWith(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            // Options — vertical stacked list, one full-width row per answer.
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16.0),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: options.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final isSelected = widget.selectedIndex == index;
                  final isDisabled = widget.selectedIndex != null || widget.isHost;
                  final isCorrect = widget.correctOptionIndices?.contains(index) ?? false;
                  final isWrongPick = widget.correctOptionIndices != null &&
                      isSelected &&
                      !isCorrect;

                  return _AnswerButton(
                    text: options[index].toString(),
                    index: index,
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    isCorrect: isCorrect,
                    isWrongPick: isWrongPick,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onOptionSelected(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onPause,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("PAUSE", style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("NEXT", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width answer row. Differentiation between options comes from a
/// lettered badge, not a per-option identity color+shape system — the
/// vertical list + letter badges deliberately diverge from Kahoot's 2x2
/// grid + triangle/diamond/circle/square vocabulary, while keeping its
/// red/blue/yellow/green badge palette (a kept, deliberate choice).
class _AnswerButton extends StatelessWidget {
  final String text;
  final int index;
  final bool isSelected;
  final bool isDisabled;
  final bool isCorrect;
  final bool isWrongPick;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.index,
    required this.isSelected,
    required this.isDisabled,
    this.isCorrect = false,
    this.isWrongPick = false,
    required this.onTap,
  });

  static const List<Color> _badgeColors = [
    Color(0xFFE21B3C), // Red
    Color(0xFF1368CE), // Blue
    Color(0xFFD89E00), // Yellow
    Color(0xFF26890C), // Green
  ];

  String get _letter => String.fromCharCode(65 + index); // A, B, C, D…

  @override
  Widget build(BuildContext context) {
    final badgeColor = _badgeColors[index % _badgeColors.length];
    final isRevealed = isCorrect || isWrongPick;

    Color borderColor = AppColors.outline.withValues(alpha: 0.15);
    if (isCorrect) {
      borderColor = context.accentColor;
    } else if (isWrongPick) {
      borderColor = AppColors.error;
    } else if (isSelected) {
      borderColor = context.accentColor;
    }

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isDisabled && !isSelected && !isRevealed ? 0.3 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isCorrect
                ? context.accentColor
                : isWrongPick
                    ? AppColors.error.withValues(alpha: 0.12)
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: (isSelected || isRevealed) ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _letter,
                  style: AppTypography.bodyLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  text,
                  style: AppTypography.bodyLarge.copyWith(
                    color: isCorrect ? Colors.black : AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isCorrect)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: Colors.black, size: 22),
                )
              else if (isSelected && !isRevealed)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: context.accentColor, size: 22),
                ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: (index * 80).ms).slideX(begin: 0.08, end: 0),
    );
  }
}

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

  const ChallengeScreen({
    super.key,
    required this.question,
    required this.timeLeft,
    this.selectedIndex,
    required this.onOptionSelected,
    this.isHost = false,
    this.onPause,
    this.onNext,
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
      bottomNavigationBar: widget.isHost ? _buildHostControls() : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Question Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
                  
                  const SizedBox(height: 24),
                  
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

            // Options Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final isSelected = widget.selectedIndex == index;
                    final isDisabled = widget.selectedIndex != null || widget.isHost;
                    
                    return _AnswerButton(
                      text: options[index].toString(),
                      index: index,
                      isSelected: isSelected,
                      isDisabled: isDisabled,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        widget.onOptionSelected(index);
                      },
                    );
                  },
                ),
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

class _AnswerButton extends StatelessWidget {
  final String text;
  final int index;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.index,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  static const List<Color> _colors = [
    Color(0xFFE21B3C), // Red
    Color(0xFF1368CE), // Blue
    Color(0xFFD89E00), // Yellow
    Color(0xFF26890C), // Green
    Color(0xFF8C17FF), // Purple
    Color(0xFFFF33A1), // Pink
  ];

  static const List<String> _shapes = [
    '<svg viewBox="0 0 50 50"><polygon points="25,5 50,45 0,45" fill="white" /></svg>',
    '<svg viewBox="0 0 50 50"><polygon points="25,0 50,25 25,50 0,25" fill="white" /></svg>',
    '<svg viewBox="0 0 50 50"><circle cx="25" cy="25" r="22" fill="white" /></svg>',
    '<svg viewBox="0 0 50 50"><rect x="5" y="5" width="40" height="40" fill="white" /></svg>',
    '<svg viewBox="0 0 50 50"><path d="M25,0 L47,13 L47,38 L25,50 L3,38 L3,13 Z" fill="white" /></svg>',
    '<svg viewBox="0 0 50 50"><path d="M25,0 L32,15 L50,18 L38,32 L40,50 L25,40 L10,50 L12,32 L0,18 L18,15 Z" fill="white" /></svg>',
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];
    
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isDisabled && !isSelected ? 0.3 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: isSelected ? Border.all(color: Colors.white, width: 4) : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Stack(
            children: [
              // Shape Icon
              Positioned(
                left: 12,
                top: 12,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: SvgPicture.string(
                    _shapes[index % _shapes.length],
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
              ),
              // Text
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: (index * 100).ms).scale(begin: const Offset(0.8, 0.8)),
    );
  }
}

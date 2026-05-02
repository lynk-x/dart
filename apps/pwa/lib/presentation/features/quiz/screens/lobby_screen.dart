import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_animate/flutter_animate.dart';

class LobbyScreen extends StatelessWidget {
  final Map<String, dynamic> questionnaire;
  final bool isHost;
  final VoidCallback? onStart;

  const LobbyScreen({
    super.key,
    required this.questionnaire,
    this.isHost = false,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              
              // Brand Logo/Text
              Column(
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AppTypography.h1.copyWith(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                      children: [
                        const TextSpan(text: 'Quiz '),
                        TextSpan(
                          text: 'Live!',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    questionnaire['title']?.toString().toUpperCase() ?? 'UNTITLED QUIZ',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primaryText,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
              
              const SizedBox(height: 48),
              
              // Interaction Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outline, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      isHost 
                        ? "You are the host. Once everyone has joined, start the quiz."
                        : (questionnaire['info']?['description']?.toString() ?? "Waiting for the host to start..."),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.alternate,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (isHost)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: onStart,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                "START QUIZ",
                                style: AppTypography.labelLarge.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 3,
                        ),
                      ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.9, 0.9)),
              
              const Spacer(),
              
              Text(
                "The game will begin shortly.",
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.alternate.withValues(alpha: 0.5),
                ),
              ).animate().fadeIn(delay: 600.ms),
              
              const SizedBox(height: 32),
              
              // Exit Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  "EXIT LOBBY",
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.error,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

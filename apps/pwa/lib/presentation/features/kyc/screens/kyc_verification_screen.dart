import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';

import '../cubit/kyc_cubit.dart';
import '../cubit/kyc_state.dart';
import '../widgets/kyc_requirements_form.dart';

Uint8List _bytesOf(List<int> bytes) => Uint8List.fromList(bytes);

/// Identity verification wizard: fetches dynamic per-country/account-type
/// requirements, walks the user through info -> documents -> confirm, and
/// submits one verification attempt. Also renders the current status
/// (pending/approved/rejected) when a prior attempt already exists.
class KycVerificationScreen extends StatelessWidget {
  const KycVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KycCubit()..load(),
      child: const _KycView(),
    );
  }
}

class _KycView extends StatelessWidget {
  const _KycView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'Identity Verification',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<KycCubit, KycState>(
          listenWhen: (a, b) => a.pendingReviewFile == null && b.pendingReviewFile != null,
          listener: (context, state) => _showPendingReviewSheet(context),
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null && state.requirements.isEmpty && state.status == KycStatus.notStarted) {
              return _ErrorState(message: state.error!, onRetry: () => context.read<KycCubit>().load());
            }
            if (state.submitted) {
              return const _SubmittedState();
            }
            if (state.status == KycStatus.pending) {
              return const _StatusState(
                icon: Icons.hourglass_top_rounded,
                iconColor: Colors.amber,
                title: 'Verification Pending',
                message:
                    'Your documents are under review. This usually takes 1-2 business days — '
                    "we'll notify you once a decision has been made.",
              );
            }
            if (state.status == KycStatus.approved) {
              return const _StatusState(
                icon: Icons.verified_rounded,
                iconColor: Color(0xFF20F928),
                title: 'You’re Verified',
                message: 'Your identity has been verified. You have full access to withdrawals and payouts.',
              );
            }
            return const _WizardBody();
          },
        ),
      ),
    );
  }

  void _showPendingReviewSheet(BuildContext context) {
    final cubit = context.read<KycCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.tertiary,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return BlocBuilder<KycCubit, KycState>(
          bloc: cubit,
          builder: (context, state) {
            final file = state.pendingReviewFile;
            if (file == null) {
              // Review resolved (confirmed/retaken) — close the sheet.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
              });
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Is this photo clear and readable?',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.memory(_bytesOf(file.bytes), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Check that all corners and text are visible, with no glare or blur.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => cubit.retakePendingReview(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Retake', style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => cubit.confirmPendingReview(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.accentColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Use This Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _WizardBody extends StatelessWidget {
  const _WizardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycCubit, KycState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIndicator(step: state.step),
              const SizedBox(height: 24),
              if (state.rejectionReason != null) ...[
                _RejectionBanner(reason: state.rejectionReason!),
                const SizedBox(height: 16),
              ],
              if (state.error != null) ...[
                _ErrorBanner(message: state.error!),
                const SizedBox(height: 16),
              ],
              switch (state.step) {
                KycStep.info => _InfoStep(state: state),
                KycStep.documents => _DocumentsStep(state: state),
                KycStep.confirm => const _ConfirmStep(),
              },
            ],
          ),
        );
      },
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final KycStep step;
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    final index = KycStep.values.indexOf(step);
    const labels = ['Your Info', 'Documents', 'Confirm'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              _Dot(active: i <= index),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: i < index ? context.accentColor : Colors.white12,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in labels)
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? context.accentColor : Colors.white12,
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final KycState state;
  const _InfoStep({required this.state});

  @override
  Widget build(BuildContext context) {
    final satisfied = state.isSatisfied(state.textRequirements);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tell us a few details before uploading your documents.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        KycRequirementsForm(
          requirements: state.textRequirements,
          emptyStateHint: 'No additional information needed — continue to documents.',
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          text: 'Continue',
          onPressed: satisfied ? () => context.read<KycCubit>().goToStep(KycStep.documents) : null,
        ),
      ],
    );
  }
}

class _DocumentsStep extends StatelessWidget {
  final KycState state;
  const _DocumentsStep({required this.state});

  @override
  Widget build(BuildContext context) {
    final satisfied = state.isSatisfied(state.fileRequirements);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upload your identification documents to verify your account.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        KycRequirementsForm(
          requirements: state.fileRequirements,
          emptyStateHint: 'You are good to go!',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.read<KycCubit>().goToStep(KycStep.info),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Go Back', style: TextStyle(color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                text: 'Continue',
                onPressed: satisfied ? () => context.read<KycCubit>().goToStep(KycStep.confirm) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycCubit, KycState>(
      builder: (context, state) {
        final canSubmit = state.consentAccepted && state.accuracyConfirmed && !state.isSubmitting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review & Confirm',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Please confirm the following before we submit your verification for review.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _ConsentCheckbox(
              value: state.accuracyConfirmed,
              onChanged: (v) => context.read<KycCubit>().setAccuracyConfirmed(v),
              label: 'I confirm that the documents and information I submitted are accurate, '
                  'genuinely mine and match the identity I am verifying.',
            ),
            const SizedBox(height: 12),
            _ConsentCheckbox(
              value: state.consentAccepted,
              onChanged: (v) => context.read<KycCubit>().setConsentAccepted(v),
              label: 'I consent to Lynk-X processing and securely storing this data for the '
                  'purpose of identity verification, in line with the Privacy Policy.',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        state.isSubmitting ? null : () => context.read<KycCubit>().goToStep(KycStep.documents),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Go Back', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    text: state.isSubmitting ? 'Processing...' : 'Submit Documents',
                    isLoading: state.isSubmitting,
                    onPressed: canSubmit ? () => context.read<KycCubit>().submit() : null,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const _ConsentCheckbox({required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: context.accentColor,
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white38),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectionBanner extends StatelessWidget {
  final String reason;
  const _RejectionBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFd32f2f).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFd32f2f).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your previous submission was rejected',
              style: TextStyle(color: Color(0xFFef5350), fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(reason, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 4),
          const Text('Please address the issue above before resubmitting.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFd32f2f).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFef5350), fontSize: 12.5)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 40),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 20),
            TextButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}

class _SubmittedState extends StatelessWidget {
  const _SubmittedState();

  @override
  Widget build(BuildContext context) {
    return const _StatusState(
      icon: Icons.check_circle_outline_rounded,
      iconColor: Color(0xFF20F928),
      title: 'Documents Submitted',
      message: 'Your verification is now pending review. This usually takes 1-2 business days — '
          "we'll notify you once a decision has been made. You can check your status anytime from here.",
    );
  }
}

class _StatusState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;

  const _StatusState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.1),
              ),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 28),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Wallet', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

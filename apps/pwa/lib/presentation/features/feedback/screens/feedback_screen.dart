import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_io/io.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _feedbackController = TextEditingController();
  String _selectedCategory = 'Feature Request';
  bool _isSubmitting = false;
  bool _includeDeviceInfo = false;

  final List<Map<String, dynamic>> _categories = [
    {
      'name': 'Bug Report',
      'id': 'bug_report',
      'icon': Icons.bug_report_outlined
    },
    {
      'name': 'Feature Request',
      'id': 'feature_request',
      'icon': Icons.lightbulb_outline
    },
    {
      'name': 'UX Improvement',
      'id': 'ux_improvement',
      'icon': Icons.auto_awesome_outlined
    },
    {'name': 'Other', 'id': 'other', 'icon': Icons.more_horiz_outlined},
  ];

  String get _selectedCategoryId =>
      _categories.firstWhere((c) => c['name'] == _selectedCategory)['id'];

  Future<void> _submitFeedback() async {
    if (_feedbackController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final packageInfo = await PackageInfo.fromPlatform();
      final user = supabase.auth.currentUser;

      // Unify feedback into the main support_tickets table for admin visibility
      await supabase.from('support_tickets').insert({
        'user_id': user?.id,
        'email': user?.email ?? 'anonymous@lynk-x.app',
        'full_name': user?.userMetadata?['full_name'] ?? 'PWA User',
        'subject': 'PWA Feedback: $_selectedCategory',
        'message': _feedbackController.text.trim(),
        'metadata': {
          'category': _selectedCategoryId,
          'app_version': packageInfo.version,
          if (_includeDeviceInfo) ...{
            'platform': Platform.operatingSystem,
            'os_version': Platform.operatingSystemVersion,
          },
        },
      });

      if (mounted) {
        setState(() => _isSubmitting = false);
        _feedbackController.clear();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.tertiary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title:
                const Text('Thank You!', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Your feedback helps us make lynk-x better for everyone.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop();
                },
                child: const Text('Close',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting feedback: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.feedback,
          style: AppTypography.interTight(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How can we help?',
              style: AppTypography.interTight(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a category and let us know what is on your mind.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),

            // Category Selection
            // Responsive columns: 2 on phone, 4 on tablet/desktop
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Breakpoints.gridColumns(context),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.5,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat['name'];

                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat['name']),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : Colors.white12,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          cat['icon'],
                          color:
                              isSelected ? AppColors.primary : Colors.white60,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          cat['name'],
                          style: TextStyle(
                            color:
                                isSelected ? AppColors.primary : Colors.white60,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Text Field
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _feedbackController,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Type your message here...',
                  hintStyle: TextStyle(color: Colors.white30),
                  border: InputBorder.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Diagnostic info opt-in
            GestureDetector(
              onTap: () => setState(() => _includeDeviceInfo = !_includeDeviceInfo),
              child: Row(
                children: [
                  Checkbox(
                    value: _includeDeviceInfo,
                    onChanged: (v) => setState(() => _includeDeviceInfo = v ?? false),
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  const Expanded(
                    child: Text(
                      'Include device info (OS & version) to help diagnose bugs',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            PrimaryButton(
              text: 'Submit Feedback',
              isLoading: _isSubmitting,
              onPressed: _submitFeedback,
            ),
          ],
        ),
      ),
    );
  }
}

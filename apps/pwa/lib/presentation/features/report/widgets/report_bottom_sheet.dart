import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The type of content being reported — maps to the reports table constraint
/// that requires exactly one target.
enum ReportTargetType { user, event, message, adAsset }

/// Shows a report bottom sheet. Call this from any screen where users can
/// report content.
///
/// Example:
/// ```dart
/// showReportSheet(context, targetType: ReportTargetType.user, targetId: userId);
/// ```
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  // For forum messages which use a composite PK
  DateTime? messageCreatedAt,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      messageCreatedAt: messageCreatedAt,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final ReportTargetType targetType;
  final String targetId;
  final DateTime? messageCreatedAt;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    this.messageCreatedAt,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  List<Map<String, dynamic>> _reasons = [];
  String? _selectedReasonId;
  final _descriptionController = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadReasons() async {
    try {
      final data = await Supabase.instance.client
          .from('report_reasons')
          .select('id, category, description')
          .eq('is_active', true)
          .order('category');

      setState(() {
        _reasons = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load report reasons';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedReasonId == null) return;

    setState(() => _isSubmitting = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final row = <String, dynamic>{
      'reporter_id': userId,
      'reason_id': _selectedReasonId,
      'info': {
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
      },
    };

    // Set exactly one target field per the CHECK constraint
    switch (widget.targetType) {
      case ReportTargetType.user:
        row['target_user_id'] = widget.targetId;
        break;
      case ReportTargetType.event:
        row['target_event_id'] = widget.targetId;
        break;
      case ReportTargetType.message:
        row['target_message_id'] = widget.targetId;
        if (widget.messageCreatedAt != null) {
          row['target_message_created_at'] =
              widget.messageCreatedAt!.toUtc().toIso8601String();
        }
        break;
      case ReportTargetType.adAsset:
        row['target_variant_id'] = widget.targetId;
        break;
    }

    try {
      await Supabase.instance.client.from('reports').insert(row);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Our team will review it shortly.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String get _targetLabel {
    switch (widget.targetType) {
      case ReportTargetType.user:
        return 'User';
      case ReportTargetType.event:
        return 'Event';
      case ReportTargetType.message:
        return 'Message';
      case ReportTargetType.adAsset:
        return 'Ad';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Report $_targetLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white12),

              // Body
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00FF00)),
                      )
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.white54)))
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            children: [
                              Text(
                                'Why are you reporting this $_targetLabel?',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Reason chips
                              ..._reasons.map((reason) {
                                final isSelected =
                                    _selectedReasonId == reason['id'];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setState(() =>
                                          _selectedReasonId =
                                              reason['id'] as String),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF00FF00)
                                                  .withValues(alpha: 0.1)
                                              : Colors.white
                                                  .withValues(alpha: 0.04),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFF00FF00)
                                                    .withValues(alpha: 0.4)
                                                : Colors.white
                                                    .withValues(alpha: 0.08),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSelected
                                                  ? Icons
                                                      .radio_button_checked
                                                  : Icons
                                                      .radio_button_off,
                                              color: isSelected
                                                  ? const Color(0xFF00FF00)
                                                  : Colors.white38,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  Text(
                                                    reason['category']
                                                        as String,
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : Colors.white
                                                              .withValues(alpha: 0.8),
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (reason[
                                                              'description'] !=
                                                          null &&
                                                      (reason['description']
                                                              as String)
                                                          .isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets
                                                              .only(
                                                              top: 4),
                                                      child: Text(
                                                        reason['description']
                                                            as String,
                                                        style: TextStyle(
                                                          color: Colors
                                                              .white
                                                              .withValues(alpha: 0.4),
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),

                              const SizedBox(height: 20),

                              // Description field
                              Text(
                                'Additional details (optional)',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _descriptionController,
                                maxLines: 4,
                                maxLength: 500,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText:
                                      'Describe the issue in more detail...',
                                  hintStyle: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.3)),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.04),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF00FF00), width: 1),
                                  ),
                                  counterStyle: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.3)),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Submit button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _selectedReasonId != null &&
                                          !_isSubmitting
                                      ? _submit
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    disabledBackgroundColor:
                                        Colors.redAccent.withValues(alpha: 0.3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Submit Report',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 16),
                              Text(
                                'Reports are reviewed by our trust & safety team. '
                                'False reports may result in account restrictions.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

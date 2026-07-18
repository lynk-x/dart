import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// Shows a dialog to submit a refund request for [ticket], to be reviewed
/// by the event organizer. Unlike cancelling, the ticket stays valid until
/// the organizer approves or rejects the request.
void showRequestRefundDialog(BuildContext context, TicketModel ticket) {
  showDialog<void>(
    context: context,
    builder: (_) => RequestRefundDialog(ticket: ticket, parentContext: context),
  );
}

class RequestRefundDialog extends StatefulWidget {
  final TicketModel ticket;
  final BuildContext parentContext;

  const RequestRefundDialog({
    super.key,
    required this.ticket,
    required this.parentContext,
  });

  @override
  State<RequestRefundDialog> createState() => _RequestRefundDialogState();
}

class _RequestRefundDialogState extends State<RequestRefundDialog> {
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_isSubmitting && _reasonController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) return;

    final cubit = widget.parentContext.read<TicketCubit>();
    setState(() => _isSubmitting = true);

    await cubit.requestRefund(reason);

    if (!mounted) return;
    final state = cubit.state;
    Navigator.pop(context);

    if (!widget.parentContext.mounted) return;
    if (state.refundRequestStatus == RefundRequestStatus.success) {
      AppSnackBars.showSuccess(
        widget.parentContext,
        'Refund request submitted. The organizer will review it shortly.',
      );
    } else {
      AppSnackBars.showError(
        widget.parentContext,
        'Failed to submit refund request: ${state.refundRequestError ?? 'Unknown error'}',
      );
    }
    cubit.resetRefundRequest();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.tertiary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Request Refund',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell the organizer why you\'re requesting a refund. Your ticket '
            'stays valid until they respond.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Reason for refund',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.accentColor, width: 1),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: context.accentColor),
                )
              : Text(
                  'Submit',
                  style: TextStyle(
                    color: _canSubmit
                        ? context.accentColor
                        : context.accentColor.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'username_lookup_field.dart';

/// Shows a dialog to transfer [ticket] to another user by username or email.
void showTransferTicketDialog(BuildContext context, TicketModel ticket) {
  showDialog<void>(
    context: context,
    builder: (_) => TransferTicketDialog(ticket: ticket, parentContext: context),
  );
}

class TransferTicketDialog extends StatefulWidget {
  final TicketModel ticket;
  final BuildContext parentContext;

  const TransferTicketDialog({
    super.key,
    required this.ticket,
    required this.parentContext,
  });

  @override
  State<TransferTicketDialog> createState() => _TransferTicketDialogState();
}

class _TransferTicketDialogState extends State<TransferTicketDialog> {
  final _controller = TextEditingController();
  bool? _recipientFound;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canTransfer {
    final value = _controller.text.trim();
    if (value.isEmpty) return false;
    if (value.contains('@')) return true; // email — let RPC decide
    return _recipientFound == true;
  }

  Future<void> _doTransfer() async {
    final recipient = _controller.text.trim();
    final cubit = widget.parentContext.read<TicketCubit>();

    Navigator.pop(context);

    try {
      await cubit.transferTicket(recipient);
      if (widget.parentContext.mounted) {
        AppSnackBars.showSuccess(widget.parentContext, 'Ticket transferred successfully!');
      }
    } catch (e) {
      if (widget.parentContext.mounted) {
        AppSnackBars.showError(widget.parentContext, 'Transfer failed: ${e.toFriendlyMessage()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.tertiary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Transfer Ticket',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the username or email of the recipient.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          UsernameLookupField(
            repository: ticketRepository,
            controller: _controller,
            allowEmail: true,
            hintText: 'username or email',
            onFoundChanged: (found) => setState(() => _recipientFound = found),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: _canTransfer ? _doTransfer : null,
          child: Text(
            'Transfer',
            style: TextStyle(
              color: _canTransfer
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

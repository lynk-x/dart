import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/resell_ticket_sheet.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/transfer_ticket_dialog.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/request_refund_dialog.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// Shows a contextual bottom sheet with available ticket actions (gift, resell, refund, report).
void showTicketOptionsSheet(BuildContext context, TicketState ticketState) {
  final ticket = ticketState.ticket;
  if (ticket == null) return;

  final pendingListing = ticketState.pendingListing;
  final pendingRefundRequest = ticketState.pendingRefundRequest;
  final isValid = ticket.status.toLowerCase() == 'valid';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
      decoration: const BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (isValid) ...[
            const Divider(color: Colors.white12, height: 1),
            // Gift Ticket
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.white70),
              title: const Text('Gift Ticket',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Transfer this ticket for free',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showTransferTicketDialog(context, ticket);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            // Resell or Cancel Offer
            if (pendingListing != null)
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.orange),
                title: const Text('Cancel Resale Offer',
                    style: TextStyle(color: Colors.orange)),
                subtitle: Text(
                  'Pending offer: ${pendingListing['currency']} ${(pendingListing['asking_price'] as num).toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await context
                        .read<TicketCubit>()
                        .cancelResaleListing(pendingListing['id'] as String);
                    if (context.mounted) {
                      AppSnackBars.showSuccess(
                          context, 'Resale offer cancelled.');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      AppSnackBars.showError(context, 'Failed to cancel: $e');
                    }
                  }
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.sell_outlined, color: Colors.white70),
                title: const Text('Resell Ticket',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Sell to a specific person via wallet',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showResellTicketSheet(context, ticket);
                },
              ),
            const Divider(color: Colors.white12, height: 1),
            // Request Refund / pending status
            if (pendingRefundRequest != null)
              const ListTile(
                leading: Icon(Icons.hourglass_top, color: Colors.orange),
                title: Text('Refund Request Pending',
                    style: TextStyle(color: Colors.orange)),
                subtitle: Text(
                  'Awaiting organizer review',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.request_quote_outlined,
                    color: Colors.white70),
                title: const Text('Request Refund',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Tickets are non-refundable — the organizer may grant an exception',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showRequestRefundDialog(context, ticket);
                },
              ),
          ],
          const Divider(color: Colors.white12, height: 1),
          // Report an Issue
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text('Report an Issue',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: Text(
              'Ref: #${ticket.displayCode}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              context.push('/feedback');
            },
          ),
        ],
      ),
    ),
  );
}

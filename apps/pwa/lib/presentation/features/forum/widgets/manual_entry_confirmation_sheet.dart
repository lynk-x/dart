import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// "Confirm Manual Entry" bottom sheet shown after a staff member types a ticket code instead of
/// scanning it: previews the holder, tier and status from the offline ticket registry so a wrong
/// code is caught before the ticket is admitted. [ticket] is null when the code isn't found.
class ManualEntryConfirmationSheet extends StatelessWidget {
  final String code;
  final Map<String, dynamic>? ticket;

  /// Called after the sheet has closed itself, when staff tap "Confirm Entry".
  final VoidCallback onConfirm;

  const ManualEntryConfirmationSheet({
    super.key,
    required this.code,
    required this.ticket,
    required this.onConfirm,
  });

  static void show(
    BuildContext context, {
    required String code,
    required Map<String, dynamic>? ticket,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ManualEntryConfirmationSheet(
        code: code,
        ticket: ticket,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A local, so the `isNotFound` checks below promote it to non-null (a field can't be).
    final ticket = this.ticket;
    final bool isNotFound = ticket == null;
    final String holderName = isNotFound ? '' : (ticket['holder_name']?.toString() ?? 'Attendee');
    final String refCode = TicketModel.formatCleanReference(ticket?['reference']?.toString() ?? ticket?['ticket_code']?.toString() ?? code);
    final String tierName = isNotFound ? '' : (ticket['tier_name']?.toString() ?? 'General Admission');
    final String rawStatus = ticket?['status']?.toString() ?? (isNotFound ? 'NotFound' : 'valid');
    final bool isAlreadyUsed = rawStatus.toLowerCase() == 'used';

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        32 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.pin_outlined, color: Colors.white70, size: 22),
              const SizedBox(width: 8),
              Text(
                'Confirm Manual Entry',
                style: AppTypography.interTight(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isAlreadyUsed
                    ? Colors.orange.withValues(alpha: 0.5)
                    : (ticket == null
                        ? Colors.red.withValues(alpha: 0.5)
                        : context.accentColor.withValues(alpha: 0.4)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#$refCode',
                      style: AppTypography.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAlreadyUsed
                            ? Colors.orange.withValues(alpha: 0.2)
                            : (ticket == null
                                ? Colors.red.withValues(alpha: 0.2)
                                : context.accentColor.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAlreadyUsed
                            ? 'ALREADY USED'
                            : (ticket == null ? 'NOT FOUND' : rawStatus.toUpperCase()),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isAlreadyUsed
                              ? Colors.orange
                              : (ticket == null ? Colors.redAccent : context.accentColor),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                Text(
                  'HOLDER NAME',
                  style: AppTypography.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  holderName,
                  style: AppTypography.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'TICKETING TIER',
                  style: AppTypography.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tierName,
                  style: AppTypography.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (isNotFound)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      onConfirm();
                    },
                    child: const Text(
                      'Confirm Entry',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

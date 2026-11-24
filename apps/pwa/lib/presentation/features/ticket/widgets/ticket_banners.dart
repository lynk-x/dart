import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// Banner indicating a pending resale offer with active countdown ticker.
class TicketPendingOfferBanner extends StatefulWidget {
  final Map<String, dynamic> listing;

  const TicketPendingOfferBanner({
    super.key,
    required this.listing,
  });

  @override
  State<TicketPendingOfferBanner> createState() =>
      _TicketPendingOfferBannerState();
}

class _TicketPendingOfferBannerState extends State<TicketPendingOfferBanner> {
  Timer? _countdownTimer;
  Duration? _remaining;
  DateTime? _trackedExpiry;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _checkAndStartCountdown();
  }

  @override
  void didUpdateWidget(covariant TicketPendingOfferBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listing['expires_at'] != widget.listing['expires_at']) {
      _checkAndStartCountdown();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _checkAndStartCountdown() {
    final expiresAt =
        DateTime.tryParse(widget.listing['expires_at'] as String? ?? '');
    if (expiresAt != null) {
      if (_trackedExpiry == expiresAt) return;
      _trackedExpiry = expiresAt;
      _countdownTimer?.cancel();
      final diff = expiresAt.toLocal().difference(DateTime.now());
      _remaining = diff.isNegative ? Duration.zero : diff;
      _countdownTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _tick(expiresAt));
    }
  }

  void _tick(DateTime expiresAt) {
    if (!mounted) return;
    final diff = expiresAt.toLocal().difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    if (diff.inSeconds <= 0) _countdownTimer?.cancel();
  }

  String _formatCountdown(Duration d) {
    if (d.inHours >= 1) {
      return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m left';
    }
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s left';
  }

  Future<void> _cancelResale(String listingId) async {
    final cubit = context.read<TicketCubit>();
    setState(() => _isCancelling = true);
    try {
      await cubit.cancelResaleListing(listingId);
      if (mounted) {
        AppSnackBars.showSuccess(context, 'Resale offer cancelled.');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showError(context, 'Failed to cancel: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.listing['currency'] as String? ?? '';
    final price = (widget.listing['asking_price'] as num).toStringAsFixed(2);
    final expiresAt =
        DateTime.tryParse(widget.listing['expires_at'] as String? ?? '');

    final expiresText = _remaining != null
        ? _formatCountdown(_remaining!)
        : (expiresAt != null
            ? 'Expires ${DateFormat('dd/MM HH:mm').format(expiresAt.toLocal())}'
            : '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_outlined, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resale Offer Pending — $currency $price',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (expiresText.isNotEmpty)
                  Text(
                    expiresText,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (_isCancelling)
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange,
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => _cancelResale(widget.listing['id'] as String),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Banner indicating a pending refund request awaiting organizer review.
class TicketPendingRefundBanner extends StatelessWidget {
  final Map<String, dynamic> request;

  const TicketPendingRefundBanner({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_top, color: Colors.orange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refund Request Pending',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Awaiting organizer review',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

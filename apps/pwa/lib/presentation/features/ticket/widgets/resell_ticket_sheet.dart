import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'username_lookup_field.dart';

/// Shows a bottom sheet to list [ticket] for resale to a specific recipient.
void showResellTicketSheet(BuildContext context, TicketModel ticket) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResellTicketSheet(ticket: ticket, parentContext: context),
  );
}

class ResellTicketSheet extends StatefulWidget {
  final TicketModel ticket;
  final BuildContext parentContext;

  const ResellTicketSheet({super.key, required this.ticket, required this.parentContext});

  @override
  State<ResellTicketSheet> createState() => _ResellTicketSheetState();
}

class _ResellTicketSheetState extends State<ResellTicketSheet> {
  final _usernameController = TextEditingController();
  final _priceController = TextEditingController();
  bool? _recipientFound;
  bool _isSubmitting = false;

  double? get _maxPrice => widget.ticket.purchasedPrice;
  String get _currency => widget.ticket.purchasedCurrency ?? '';

  @override
  void initState() {
    super.initState();
    // Pre-fill price with max allowed
    if (_maxPrice != null) {
      _priceController.text = _maxPrice!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_isSubmitting) return false;
    if (_recipientFound != true) return false;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) return false;
    if (_maxPrice != null && price > _maxPrice!) return false;
    return true;
  }

  Future<void> _submit() async {
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) return;

    final cubit = widget.parentContext.read<TicketCubit>();
    setState(() => _isSubmitting = true);

    try {
      await cubit.createResaleListing(
        recipientUsername: _usernameController.text.trim(),
        askingPrice: price,
      );
      if (mounted) Navigator.pop(context);
      if (widget.parentContext.mounted) {
        AppSnackBars.showSuccess(widget.parentContext, 'Resale offer sent! Buyer has 48 hours to accept.');
      }
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      if (widget.parentContext.mounted) {
        AppSnackBars.showError(widget.parentContext, 'Failed: ${e.toFriendlyMessage()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text(
            'Resell Ticket',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (_maxPrice != null)
            Text(
              'Max price: $_currency ${_maxPrice!.toStringAsFixed(2)} (original purchase price)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          const SizedBox(height: 20),
          // Recipient
          const Text('Recipient Username', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          UsernameLookupField(
            repository: ticketRepository,
            controller: _usernameController,
            hintText: 'username',
            onFoundChanged: (found) => setState(() => _recipientFound = found),
          ),
          const SizedBox(height: 16),
          // Price
          const Text('Asking Price', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: const TextStyle(color: Colors.white30),
              prefixText: _currency.isNotEmpty ? '$_currency ' : null,
              prefixStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.accentColor, width: 1)),
            ),
          ),
          if (_maxPrice != null && (double.tryParse(_priceController.text.trim()) ?? 0) > _maxPrice!) ...[
            const SizedBox(height: 6),
            Text(
              'Price cannot exceed the original purchase price of $_currency ${_maxPrice!.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Payment is wallet-to-wallet. No platform fee.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          const SizedBox(height: 24),
          _isSubmitting
              ? Center(child: CircularProgressIndicator(color: context.accentColor))
              : PrimaryButton(
                  text: 'Send Resale Offer',
                  onPressed: _canSubmit ? _submit : null,
                ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}

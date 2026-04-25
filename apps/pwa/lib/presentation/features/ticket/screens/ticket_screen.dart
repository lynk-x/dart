import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:add_2_calendar/add_2_calendar.dart' as add_2_calendar;
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

class TicketPage extends StatelessWidget {
  final String? ticketId;

  const TicketPage({super.key, this.ticketId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TicketCubit()..loadTicket(ticketId ?? ''),
      child: const TicketView(),
    );
  }
}

class TicketView extends StatelessWidget {
  const TicketView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Image.asset(
          'packages/core/assets/images/lynk-x_combined-logo.png',
          width: 200,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, size: 28, color: Colors.white),
            tooltip: 'Ticket options',
            onPressed: () {
              final state = context.read<TicketCubit>().state;
              if (state.ticket != null) {
                _showTicketOptions(context, state);
              }
            },
          ),
        ],
      ),
      body: BlocListener<TicketCubit, TicketState>(
        listenWhen: (p, c) => p.ticket?.isRedeemed == false && c.ticket?.isRedeemed == true,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ticket Redeemed Safely — Enjoy the event!'),
                ],
              ),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        },
        child: BlocBuilder<TicketCubit, TicketState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load ticket',
                    style: AppTypography.inter(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.read<TicketCubit>().refresh(),
                    child: const Text('Retry',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            );
          }

          if (state.ticket == null) {
            return Center(
              child: Text(
                'Ticket not found',
                style: AppTypography.inter(color: Colors.white),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => context.read<TicketCubit>().refresh(),
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Constrain card width on tablets/desktops (max 500px)
                  Breakpoints.constrain(
                    _buildTicketCard(state.ticket!)
                        .animate()
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad)
                        .fadeIn(),
                    maxWidth: Breakpoints.maxCardWidth,
                  ),
                  if (state.pendingListing != null) ...[
                    const SizedBox(height: 16),
                    Breakpoints.constrain(
                      _buildPendingOfferBanner(context, state.pendingListing!),
                      maxWidth: Breakpoints.maxCardWidth,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Show this ticket at the entrance',
                    style: AppTypography.inter(
                      fontSize: 14,
                      color: AppColors.secondaryText.withValues(alpha: 0.5),
                    ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Shows a contextual bottom sheet with available ticket actions.
  void _showTicketOptions(BuildContext context, TicketState ticketState) {
    final ticket = ticketState.ticket!;
    final pendingListing = ticketState.pendingListing;
    final isValid = ticket.status.toLowerCase() == 'valid';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Add to Calendar
            ListTile(
              leading: const Icon(Icons.calendar_month, color: AppColors.primary),
              title: const Text('Add to Calendar', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                '${DateFormat('dd/MM/yyyy HH:mm').format(ticket.startsAt)} • ${ticket.locationName}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                add_2_calendar.Add2Calendar.addEvent2Cal(add_2_calendar.Event(
                  title: ticket.eventTitle,
                  startDate: ticket.startsAt,
                  endDate: ticket.endsAt,
                  location: ticket.locationName,
                  description: 'Lynk-X ticket reference: #${ticket.ticketCode}',
                ));
              },
            ),
            if (isValid) ...[
              const Divider(color: Colors.white12, height: 1),
              // Gift Ticket
              ListTile(
                leading: const Icon(Icons.card_giftcard, color: Colors.white70),
                title: const Text('Gift Ticket', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Transfer this ticket for free',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showTransferDialog(context, ticket);
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              // Resell or Cancel Offer
              if (pendingListing != null)
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.orange),
                  title: const Text('Cancel Resale Offer', style: TextStyle(color: Colors.orange)),
                  subtitle: Text(
                    'Pending offer: ${pendingListing['currency']} ${(pendingListing['asking_price'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _cancelResaleListing(context, pendingListing['id'] as String);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.sell_outlined, color: Colors.white70),
                  title: const Text('Resell Ticket', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Sell to a specific person via wallet',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showResellSheet(context, ticket);
                  },
                ),
            ],
            const Divider(color: Colors.white12, height: 1),
            // Report an Issue
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: const Text('Report an Issue', style: TextStyle(color: Colors.redAccent)),
              subtitle: Text(
                'Ref: #${ticket.ticketCode}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/feedback');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _cancelResaleListing(BuildContext context, String listingId) async {
    final cubit = context.read<TicketCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await cubit.cancelResaleListing(listingId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Resale offer cancelled.'), backgroundColor: AppColors.primary),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to cancel: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showResellSheet(BuildContext context, TicketModel ticket) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResellTicketSheet(ticket: ticket, parentContext: context),
    );
  }

  /// Shows a dialog to transfer the ticket to another user.
  void _showTransferDialog(BuildContext context, TicketModel ticket) {
    showDialog<void>(
      context: context,
      builder: (_) => _TransferTicketDialog(
        ticket: ticket,
        parentContext: context,
      ),
    );
  }

  Widget _buildPendingOfferBanner(BuildContext context, Map<String, dynamic> listing) {
    final currency = listing['currency'] as String? ?? '';
    final price = (listing['asking_price'] as num).toStringAsFixed(2);
    final expiresAt = DateTime.tryParse(listing['expires_at'] as String? ?? '');
    final expiresText = expiresAt != null
        ? 'Expires ${DateFormat('dd/MM HH:mm').format(expiresAt.toLocal())}'
        : '';

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
                  style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (expiresText.isNotEmpty)
                  Text(expiresText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancelResaleListing(context, listing['id'] as String),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Cancel', style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(TicketModel ticket) {
    // Use dd/MM/yyyy and 24-hour format (international standard)
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');
    final statusColor = ticket.status.toLowerCase() == 'valid'
        ? AppColors.primary
        : Colors.orange;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.eventTitle,
                        style: AppTypography.interTight(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color:
                                AppColors.secondaryText.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ticket.locationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.inter(
                                fontSize: 14,
                                color: AppColors.secondaryText
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 16,
                            color:
                                AppColors.secondaryText.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${dateFormat.format(ticket.startsAt)} • ${timeFormat.format(ticket.startsAt)}',
                            style: AppTypography.inter(
                              fontSize: 14,
                              color: AppColors.secondaryText
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: ticket.thumbnailUrl ?? '',
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.secondaryBackground,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.secondaryBackground,
                      child: const Icon(Icons.music_note,
                          size: 30, color: AppColors.secondaryText),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Dashed Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: CustomPaint(
              size: const Size(double.infinity, 1),
              painter: DashedLinePainter(
                color: AppColors.secondaryText.withValues(alpha: 0.3),
              ),
            ),
          ),

          // Name and Status Section
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOLDER',
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ticket.holderName,
                        style: AppTypography.interTight(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'STATUS',
                      style: AppTypography.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryText.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryText.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        ticket.isRedeemed
                            ? 'REDEEMED'
                            : ticket.status.toUpperCase(),
                        style: AppTypography.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tier Section
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIER',
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ticket.tierName.toUpperCase(),
                        style: AppTypography.interTight(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Barcode Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: ticket.ticketCode,
                  drawText: false,
                  color: Colors.black,
                  height: 60,
                  width: double.infinity,
                ),
                const SizedBox(height: 8),
                Text(
                  '#${ticket.ticketCode}',
                  style: AppTypography.inter(
                    fontSize: 14,
                    color: Colors.black45,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferTicketDialog extends StatefulWidget {
  final TicketModel ticket;
  final BuildContext parentContext;

  const _TransferTicketDialog({
    required this.ticket,
    required this.parentContext,
  });

  @override
  State<_TransferTicketDialog> createState() => _TransferTicketDialogState();
}

class _TransferTicketDialogState extends State<_TransferTicketDialog> {
  final _controller = TextEditingController();
  Timer? _debounceTimer;
  bool _isChecking = false;
  bool? _recipientFound;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onInputChanged);
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final value = _controller.text.trim();

    if (value.isEmpty || value.length < 3) {
      _debounceTimer?.cancel();
      if (mounted) setState(() { _recipientFound = null; _isChecking = false; });
      return;
    }

    // Email addresses: skip lookup, let the RPC validate
    if (value.contains('@')) {
      _debounceTimer?.cancel();
      if (mounted) setState(() { _recipientFound = null; _isChecking = false; });
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    setState(() => _isChecking = true);

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      try {
        final data = await Supabase.instance.client
            .from('user_profile')
            .select('user_name')
            .eq('user_name', value)
            .maybeSingle();
        if (mounted) {
          setState(() {
            _recipientFound = data != null;
            _isChecking = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isChecking = false);
      }
    });
  }

  bool get _canTransfer {
    final value = _controller.text.trim();
    if (value.isEmpty || _isChecking) return false;
    if (value.contains('@')) return true; // email — let RPC decide
    return _recipientFound == true;
  }

  Future<void> _doTransfer() async {
    final recipient = _controller.text.trim();
    // Capture refs before closing the dialog
    final messenger = ScaffoldMessenger.of(widget.parentContext);
    final cubit = widget.parentContext.read<TicketCubit>();
    Navigator.pop(context);

    try {
      await Supabase.instance.client.rpc('transfer_ticket', params: {
        'p_ticket_id': widget.ticket.id,
        'p_recipient_username': recipient,
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ticket transferred successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
      cubit.refresh();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Transfer failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget? _suffixIcon() {
    if (_isChecking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
        ),
      );
    }
    if (_controller.text.contains('@')) return null;
    if (_recipientFound == true) return const Icon(Icons.check_circle, color: AppColors.primary, size: 20);
    if (_recipientFound == false) return const Icon(Icons.error, color: Colors.redAccent, size: 20);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.text.trim();
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
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'username or email',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1),
              ),
              suffixIcon: _suffixIcon(),
            ),
          ),
          if (value.length >= 3 && !value.contains('@') && !_isChecking) ...[
            const SizedBox(height: 8),
            if (_recipientFound == false)
              const Text(
                'No user found with that username.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              )
            else if (_recipientFound == true)
              Text(
                'Recipient found.',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
          ],
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
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.3),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResellTicketSheet extends StatefulWidget {
  final TicketModel ticket;
  final BuildContext parentContext;

  const _ResellTicketSheet({required this.ticket, required this.parentContext});

  @override
  State<_ResellTicketSheet> createState() => _ResellTicketSheetState();
}

class _ResellTicketSheetState extends State<_ResellTicketSheet> {
  final _usernameController = TextEditingController();
  final _priceController = TextEditingController();
  Timer? _debounceTimer;
  bool _isChecking = false;
  bool? _recipientFound;
  bool _isSubmitting = false;

  double? get _maxPrice => widget.ticket.purchasedPrice;
  String get _currency => widget.ticket.purchasedCurrency ?? '';

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    // Pre-fill price with max allowed
    if (_maxPrice != null) {
      _priceController.text = _maxPrice!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onUsernameChanged);
    _debounceTimer?.cancel();
    _usernameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final value = _usernameController.text.trim();
    if (value.length < 3) {
      _debounceTimer?.cancel();
      if (mounted) setState(() { _recipientFound = null; _isChecking = false; });
      return;
    }
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    setState(() => _isChecking = true);
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      try {
        final data = await Supabase.instance.client
            .from('user_profile')
            .select('user_name')
            .eq('user_name', value)
            .maybeSingle();
        if (mounted) setState(() { _recipientFound = data != null; _isChecking = false; });
      } catch (_) {
        if (mounted) setState(() => _isChecking = false);
      }
    });
  }

  bool get _canSubmit {
    if (_isChecking || _isSubmitting) return false;
    if (_recipientFound != true) return false;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) return false;
    if (_maxPrice != null && price > _maxPrice!) return false;
    return true;
  }

  Future<void> _submit() async {
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) return;

    final messenger = ScaffoldMessenger.of(widget.parentContext);
    final cubit = widget.parentContext.read<TicketCubit>();
    setState(() => _isSubmitting = true);

    try {
      await cubit.createResaleListing(
        recipientUsername: _usernameController.text.trim(),
        askingPrice: price,
      );
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Resale offer sent! Buyer has 48 hours to accept.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
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
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'username',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
              suffixIcon: _isChecking
                  ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)))
                  : (_recipientFound == true
                      ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                      : (_recipientFound == false ? const Icon(Icons.error, color: Colors.redAccent, size: 20) : null)),
            ),
          ),
          if (_recipientFound == false) ...[
            const SizedBox(height: 6),
            const Text('No user found with that username.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ] else if (_recipientFound == true) ...[
            const SizedBox(height: 6),
            Text('Recipient found.', style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 12)),
          ],
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
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Payment is wallet-to-wallet. No platform fee.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 24),
          _isSubmitting
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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

class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.dashWidth = 8.0,
    this.dashSpace = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double startX = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

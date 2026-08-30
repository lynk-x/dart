import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/resell_ticket_sheet.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/transfer_ticket_dialog.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/request_refund_dialog.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';
import 'package:lynk_x/core/utils/timezone_abbreviation.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';


class TicketPage extends StatelessWidget {
  final String? ticketReference;

  const TicketPage({super.key, this.ticketReference});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TicketCubit(ticketRepository)..loadTicket(ticketReference ?? ''),
      child: const TicketView(),
    );
  }
}

class TicketView extends StatefulWidget {
  const TicketView({super.key});

  @override
  State<TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends State<TicketView> {
  bool _isCancellingResale = false;
  Timer? _countdownTimer;
  Timer? _totpRefreshTimer;
  Duration? _remaining;
  DateTime? _trackedExpiry;

  @override
  void initState() {
    super.initState();
    _totpRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _totpRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Generates a dynamic HMAC-SHA256 TOTP payload signature valid for 30s.
  /// Anti-screenshot security feature
  String _generateTotpBarcodeData(TicketModel ticket) {
    final now = DateTime.now().toUtc();
    final epoch30s = now.millisecondsSinceEpoch ~/ 30000;
    final secretKey = ticket.secretKey ?? ticket.displayCode;
    final keyBytes = utf8.encode(secretKey);
    final messageBytes = utf8.encode('${ticket.id}:$epoch30s');
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    return '${ticket.displayCode}|$epoch30s|$digest';
  }

  void _startCountdown(DateTime expiresAt) {
    if (_trackedExpiry == expiresAt) return;
    _trackedExpiry = expiresAt;
    _countdownTimer?.cancel();
    _tick(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick(expiresAt));
  }

  void _tick(DateTime expiresAt) {
    if (!mounted) return;
    final diff = expiresAt.toLocal().difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    if (!diff.isNegative && diff.inSeconds <= 0) _countdownTimer?.cancel();
  }

  String _formatCountdown(Duration d) {
    if (d.inHours >= 1) {
      return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m left';
    }
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s left';
  }

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
          onPressed: () => context.go('/tickets'),
        ),
        title: RepaintBoundary(
          child: SvgPicture.asset(
            'assets/images/official_lynk-x_combined-logo.svg',
            width: 200,
            fit: BoxFit.contain,
          ),
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
          AppSnackBars.showSuccess(context, 'Ticket Redeemed Safely — Enjoy the event!');
        },
        child: BlocBuilder<TicketCubit, TicketState>(
        builder: (context, state) {
          if (state.isLoading) {
            return _buildTicketSkeleton(context);
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
                    child: Text('Retry',
                        style: TextStyle(color: context.accentColor)),
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
            color: context.accentColor,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const SizedBox(height: 24), // Top spacer to push everything down
                  // Constrain card width on tablets/desktops (max 920px for widescreen boarding pass)
                  Breakpoints.constrain(
                    _buildTicketCard(state.ticket!)
                        .animate()
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad)
                        .fadeIn(),
                    maxWidth: Breakpoints.isTablet(context) ? 920 : Breakpoints.maxCardWidth,
                  ),
                  if (state.pendingListing != null) ...[
                    const SizedBox(height: 16),
                    Breakpoints.constrain(
                      _buildPendingOfferBanner(context, state.pendingListing!),
                      maxWidth: Breakpoints.maxCardWidth,
                    ),
                  ],
                  if (state.pendingRefundRequest != null) ...[
                    const SizedBox(height: 16),
                    Breakpoints.constrain(
                      _buildPendingRefundBanner(state.pendingRefundRequest!),
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
    final pendingRefundRequest = ticketState.pendingRefundRequest;
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
                  showTransferTicketDialog(context, ticket);
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
                    showResellTicketSheet(context, ticket);
                  },
                ),
              const Divider(color: Colors.white12, height: 1),
              // Request Refund / pending status
              if (pendingRefundRequest != null)
                const ListTile(
                  leading: Icon(Icons.hourglass_top, color: Colors.orange),
                  title: Text('Refund Request Pending', style: TextStyle(color: Colors.orange)),
                  subtitle: Text(
                    'Awaiting organizer review',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.request_quote_outlined, color: Colors.white70),
                  title: const Text('Request Refund', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Tickets are non-refundable — the organizer may grant an exception',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showRequestRefundDialog(context, ticket);
                  },
                ),
            ],
            const Divider(color: Colors.white12, height: 1),
            // Report an Issue
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: const Text('Report an Issue', style: TextStyle(color: Colors.redAccent)),
              subtitle: Text(
                'Ref: #${ticket.displayCode}',
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

  Future<void> _cancelResaleListing(BuildContext context, String listingId) async {
    final cubit = context.read<TicketCubit>();
    setState(() => _isCancellingResale = true);
    try {
      await cubit.cancelResaleListing(listingId);
      if (context.mounted) AppSnackBars.showSuccess(context, 'Resale offer cancelled.');
    } catch (e) {
      if (context.mounted) AppSnackBars.showError(context, 'Failed to cancel: $e');
    } finally {
      if (mounted) setState(() => _isCancellingResale = false);
    }
  }

  Widget _buildPendingOfferBanner(BuildContext context, Map<String, dynamic> listing) {
    final currency = listing['currency'] as String? ?? '';
    final price = (listing['asking_price'] as num).toStringAsFixed(2);
    final expiresAt = DateTime.tryParse(listing['expires_at'] as String? ?? '');
    if (expiresAt != null) _startCountdown(expiresAt);

    final expiresText = _remaining != null
        ? _formatCountdown(_remaining!)
        : (expiresAt != null ? 'Expires ${DateFormat('dd/MM HH:mm').format(expiresAt.toLocal())}' : '');

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
          if (_isCancellingResale)
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
              ),
            )
          else
            TextButton(
              onPressed: () => _cancelResaleListing(context, listing['id'] as String),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Cancel', style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingRefundBanner(Map<String, dynamic> request) {
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
                  style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600),
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

  /// Maps ticket.status (active | used | cancelled | expired | transferred)
  /// to a display color and label. isRedeemed (status == 'used') takes
  /// priority over the raw status per the existing REDEEMED-label behavior.
  (Color, String) _statusDisplay(TicketModel ticket, BuildContext context) {
    if (ticket.isRedeemed) return (AppColors.secondaryText.withValues(alpha: 0.6), 'REDEEMED');
    switch (ticket.status.toLowerCase()) {
      case 'active':
        return (context.accentColor, 'VALID');
      case 'cancelled':
        return (AppColors.error, 'CANCELLED');
      case 'expired':
        return (AppColors.error, 'EXPIRED');
      case 'transferred':
        return (Colors.orange, 'TRANSFERRED');
      default:
        return (Colors.orange, ticket.status.toUpperCase());
    }
  }

  Widget _buildTicketCard(TicketModel ticket) {
    if (Breakpoints.isTablet(context)) {
      return _buildWidescreenBoardingPass(ticket);
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final timeFormat = DateFormat('h:mm a');
    final tzAbbr = TimezoneAbbreviation.forIana(ticket.timezone);
    final (statusColor, statusLabel) = _statusDisplay(ticket, context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.accentColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.accentColor.withValues(alpha: 0.3),
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
                            dateFormat.format(ticket.startsAt),
                            style: AppTypography.inter(
                              fontSize: 14,
                              color: AppColors.secondaryText
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color:
                                AppColors.secondaryText.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeFormat.format(ticket.startsAt) +
                                (tzAbbr != null ? ' $tzAbbr' : ''),
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
                    imageUrl: ImageOptimizer.getOptimizedUrl(
                      ticket.thumbnailUrl ?? '',
                      width: 150,
                      height: 150,
                    ),
                    memCacheWidth: 200,
                    memCacheHeight: 200,
                    cacheManager: LynkCacheManager.instance,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        color: AppColors.primaryBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        statusLabel,
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

          const SizedBox(height: 46),
          const TicketCutoutSeparator(),
          const SizedBox(height: 24),

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
                RepaintBoundary(
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: _generateTotpBarcodeData(ticket),
                    drawText: false,
                    color: Colors.black,
                    height: 60,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '#${ticket.displayCode}',
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

  Widget _buildWidescreenBoardingPass(TicketModel ticket) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final timeFormat = DateFormat('h:mm a');
    final tzAbbr = TimezoneAbbreviation.forIana(ticket.timezone);
    final (statusColor, statusLabel) = _statusDisplay(ticket, context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.accentColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.accentColor.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Main Section (64% width)
              Expanded(
                flex: 64,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Header Section: Title, Location, Date/Time & Poster Thumbnail
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ticket.eventTitle,
                                  style: AppTypography.interTight(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondaryText,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 18,
                                      color: AppColors.secondaryText
                                          .withValues(alpha: 0.75),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        ticket.locationName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.inter(
                                          fontSize: 15,
                                          color: AppColors.secondaryText
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_month,
                                      size: 18,
                                      color: AppColors.secondaryText
                                          .withValues(alpha: 0.75),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${dateFormat.format(ticket.startsAt)} • ${timeFormat.format(ticket.startsAt)}${tzAbbr != null ? " $tzAbbr" : ""}',
                                      style: AppTypography.inter(
                                        fontSize: 15,
                                        color: AppColors.secondaryText
                                            .withValues(alpha: 0.75),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(
                              imageUrl: ImageOptimizer.getOptimizedUrl(
                                ticket.thumbnailUrl ?? '',
                                width: 200,
                                height: 200,
                              ),
                              memCacheWidth: 250,
                              memCacheHeight: 250,
                              cacheManager: LynkCacheManager.instance,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.secondaryBackground,
                                child: const Icon(Icons.music_note,
                                    size: 36, color: AppColors.secondaryText),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Details Section: Holder, Tier, Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HOLDER',
                                style: AppTypography.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondaryText
                                      .withValues(alpha: 0.5),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TIER',
                                style: AppTypography.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondaryText
                                      .withValues(alpha: 0.5),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'STATUS',
                                style: AppTypography.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondaryText
                                      .withValues(alpha: 0.5),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBackground,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: statusColor, width: 1.5),
                                ),
                                child: Text(
                                  statusLabel,
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
                    ],
                  ),
                ),
              ),

              // Vertical Dashed Tear Line Divider
              CustomPaint(
                size: const Size(1, double.infinity),
                painter: VerticalDashedLinePainter(
                  color: AppColors.secondaryText.withValues(alpha: 0.35),
                  dashHeight: 8.0,
                  dashSpace: 5.0,
                ),
              ),

              // Right Stub: Barcode & Code (36% width, NO button)
              Expanded(
                flex: 36,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RepaintBoundary(
                        child: BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: _generateTotpBarcodeData(ticket),
                          drawText: false,
                          color: Colors.black,
                          height: 95,
                          width: double.infinity,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '#${ticket.displayCode}',
                        style: AppTypography.inter(
                          fontSize: 15,
                          color: Colors.black54,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VerticalDashedLinePainter extends CustomPainter {
  final Color color;
  final double dashHeight;
  final double dashSpace;

  VerticalDashedLinePainter({
    required this.color,
    this.dashHeight = 6.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double startY = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

Widget _buildTicketSkeleton(BuildContext context) {
  final isWide = MediaQuery.of(context).size.width >= 600;
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      children: [
        const SizedBox(height: 24),
        Breakpoints.constrain(
          Container(
            height: isWide ? 220 : 420,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: isWide ? 64 : 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 200,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Container(
                            width: 80,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 80,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isWide) ...[
                  const SizedBox(width: 20),
                  Container(
                    width: 1,
                    color: Colors.white12,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fade(begin: 0.3, end: 0.8, duration: 800.ms),
          maxWidth: isWide ? 920 : Breakpoints.maxCardWidth,
        ),
      ],
    ),
  );
}

class TicketCutoutSeparator extends StatelessWidget {
  final Color cutoutColor;

  const TicketCutoutSeparator({
    super.key,
    this.cutoutColor = AppColors.primaryBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: DashedLinePainter(
                  color: AppColors.secondaryText.withValues(alpha: 0.3),
                  dashWidth: 6,
                  dashSpace: 4,
                ),
              ),
            ),
          ),
          // Left cutout
          Positioned(
            left: -15,
            top: 0,
            bottom: 0,
            child: Container(
              width: 30,
              decoration: BoxDecoration(
                color: cutoutColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Right cutout
          Positioned(
            right: -15,
            top: 0,
            bottom: 0,
            child: Container(
              width: 30,
              decoration: BoxDecoration(
                color: cutoutColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


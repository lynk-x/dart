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
              // Access the ticket from the current cubit state
              final state = context.read<TicketCubit>().state;
              if (state.ticket != null) {
                _showTicketOptions(context, state.ticket!);
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
  void _showTicketOptions(BuildContext context, TicketModel ticket) {
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
            // Handle bar
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
            const Divider(color: Colors.white12, height: 1),
            // Transfer Ticket
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.white70),
              title: const Text('Transfer Ticket', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Send this ticket to another user',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showTransferDialog(context, ticket);
              },
            ),
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
                // Navigate to feedback with the ticket reference pre-noted
                context.push('/feedback');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a dialog to transfer the ticket to another user.
  void _showTransferDialog(BuildContext context, TicketModel ticket) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.tertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Transfer Ticket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the username or email of the recipient.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'username or email',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () async {
              final recipient = controller.text.trim();
              if (recipient.isEmpty) return;

              Navigator.pop(ctx);
              
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Supabase.instance.client.rpc('transfer_ticket', params: {
                  'p_ticket_id': ticket.id,
                  'p_recipient_username': recipient,
                });
                
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ticket transferred successfully!'),
                    backgroundColor: AppColors.primary,
                  ),
                );
                
                // Refresh the list if needed or pop
                if (context.mounted) {
                  context.read<TicketCubit>().refresh();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Transfer failed: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Transfer', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
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

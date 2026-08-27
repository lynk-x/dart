import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/shared/widgets/empty_state.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/tickets_list_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';

class TicketsListScreen extends StatelessWidget {
  const TicketsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TicketsListCubit(ticketRepository)..loadTickets(),
      child: const TicketsListView(),
    );
  }
}

class TicketsListView extends StatelessWidget {
  const TicketsListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 32, color: Colors.white),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          'My Tickets',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.support_agent_rounded, color: Colors.white70),
            onPressed: () {
              context.push('/support?context=events');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocBuilder<TicketsListCubit, TicketsListState>(
        builder: (context, state) {
          if (state.isLoading) {
            return Center(
              child: CircularProgressIndicator(color: context.accentColor),
            );
          }

          if (state.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${state.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          context.read<TicketsListCubit>().refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.tickets.isEmpty) {
            return const EmptyState(
              message:
                  'You have no tickets yet.\nBook your first event to see it here!',
            );
          }

          return RefreshIndicator(
            onRefresh: () => context.read<TicketsListCubit>().refresh(),
            color: context.accentColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;

                if (isWide) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.76,
                    ),
                    itemCount: state.tickets.length,
                    itemBuilder: (context, index) {
                      final ticket = state.tickets[index];
                      return RepaintBoundary(
                        key: ValueKey('ticket_grid_${ticket.reference}'),
                        child: _TicketGridItem(
                          key: ValueKey(ticket.reference),
                          ticket: ticket,
                        ),
                      );
                    },
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: state.tickets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final ticket = state.tickets[index];
                    return RepaintBoundary(
                      key: ValueKey('ticket_list_${ticket.reference}'),
                      child: _TicketListItem(
                        key: ValueKey(ticket.reference),
                        ticket: ticket,
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TicketGridItem extends StatelessWidget {
  final TicketModel ticket;

  const _TicketGridItem({required this.ticket, super.key});

  @override
  Widget build(BuildContext context) {
    final isPassed = ticket.endsAt.isBefore(DateTime.now());
    final statusLabel = ticket.isRedeemed
        ? 'REDEEMED'
        : (isPassed
            ? 'EXPIRED'
            : (ticket.status.toLowerCase() == 'active' ||
                    ticket.status.toLowerCase() == 'valid'
                ? 'VALID'
                : ticket.status.toUpperCase()));
    final statusBgColor = ticket.isRedeemed || isPassed
        ? Colors.white12
        : (ticket.status.toLowerCase() == 'active' ||
                ticket.status.toLowerCase() == 'valid'
            ? context.accentColor
            : AppColors.tertiary);
    final statusTextColor = ticket.isRedeemed || isPassed
        ? Colors.white54
        : (ticket.status.toLowerCase() == 'active' ||
                ticket.status.toLowerCase() == 'valid'
            ? Colors.black
            : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPassed
              ? Colors.white10
              : context.accentColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/ticket/${ticket.reference}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top 56% Poster Area
                Expanded(
                  flex: 56,
                  child: CachedNetworkImage(
                    imageUrl: ImageOptimizer.getOptimizedUrl(
                      ticket.thumbnailUrl ?? '',
                      width: 350,
                      height: 350,
                    ),
                    memCacheWidth: 350,
                    memCacheHeight: 350,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.tertiary,
                      child: const Icon(Icons.event,
                          color: Colors.white24, size: 40),
                    ),
                  ),
                ),

                // Bottom 44% Solid Info Dock with Barcode View Pass Button
                Expanded(
                  flex: 44,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            ticket.eventTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPassed ? Colors.white54 : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Row 3: Tier Name + Ticket Status Chip
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ticket.tierName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.accentColor
                                      .withValues(alpha: 0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusBgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: statusTextColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Barcode "View Pass" Action Button (Solid BG with Black Text)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isPassed
                                ? Colors.white24
                                : context.accentColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _CustomBarcodeIcon(
                                height: 13,
                                color: isPassed
                                    ? Colors.white54
                                    : Colors.black,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'VIEW PASS',
                                style: TextStyle(
                                  color: isPassed
                                      ? Colors.white54
                                      : Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

class _TicketListItem extends StatelessWidget {
  final TicketModel ticket;

  const _TicketListItem({required this.ticket, super.key});

  @override
  Widget build(BuildContext context) {
    final isPassed = ticket.endsAt.isBefore(DateTime.now());
    final statusLabel = ticket.isRedeemed
        ? 'REDEEMED'
        : (isPassed
            ? 'EXPIRED'
            : (ticket.status.toLowerCase() == 'active' ||
                    ticket.status.toLowerCase() == 'valid'
                ? 'VALID'
                : ticket.status.toUpperCase()));
    final statusBgColor = ticket.isRedeemed || isPassed
        ? Colors.white12
        : (ticket.status.toLowerCase() == 'active' ||
                ticket.status.toLowerCase() == 'valid'
            ? context.accentColor
            : AppColors.tertiary);
    final statusTextColor = ticket.isRedeemed || isPassed
        ? Colors.white54
        : (ticket.status.toLowerCase() == 'active' ||
                ticket.status.toLowerCase() == 'valid'
            ? Colors.black
            : Colors.white);

    return GestureDetector(
      onTap: () => context.push('/ticket/${ticket.reference}'),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Compact Event Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: ImageOptimizer.getOptimizedUrl(
                  ticket.thumbnailUrl ?? '',
                  width: 120,
                  height: 120,
                ),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  color: AppColors.tertiary,
                  child: const Icon(Icons.event, color: Colors.white24, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ticket.eventTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.tierName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.accentColor.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Ticket Status Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusTextColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Custom vector barcode icon with authentic alternating bar widths.
class _CustomBarcodeIcon extends StatelessWidget {
  final double height;
  final Color color;

  const _CustomBarcodeIcon({
    this.height = 13,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const barWidths = [1.8, 1.0, 2.5, 1.2, 2.8, 1.0, 2.2, 1.4];

    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: barWidths.map((w) {
          return Padding(
            padding: const EdgeInsets.only(right: 1.5),
            child: Container(
              width: w,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(0.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

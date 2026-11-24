import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_totp_cubit.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/ticket_card.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/ticket_banners.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/ticket_options_sheet.dart';
import 'ticket_screen_widgets.dart';

/// Ticket details page displaying ticket info, boarding pass styling,
/// and dynamic anti-screenshot HMAC TOTP barcode verification.
class TicketPage extends StatelessWidget {
  final String? ticketReference;

  const TicketPage({super.key, this.ticketReference});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              TicketCubit(ticketRepository)..loadTicket(ticketReference ?? ''),
        ),
        BlocProvider(
          create: (context) => TicketTotpCubit(),
        ),
      ],
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
          tooltip: 'Back',
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
                showTicketOptionsSheet(context, state);
              }
            },
          ),
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<TicketCubit, TicketState>(
            listenWhen: (p, c) =>
                p.ticket?.isRedeemed == false && c.ticket?.isRedeemed == true,
            listener: (context, state) {
              AppSnackBars.showSuccess(
                  context, 'Ticket Redeemed Safely — Enjoy the event!');
            },
          ),
          BlocListener<TicketCubit, TicketState>(
            listenWhen: (p, c) => p.ticket != c.ticket && c.ticket != null,
            listener: (context, state) {
              context.read<TicketTotpCubit>().setTicket(state.ticket!);
            },
          ),
        ],
        child: BlocBuilder<TicketCubit, TicketState>(
          builder: (context, state) {
            if (state.isLoading) {
              return buildTicketSkeleton(context);
            }

            if (state.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: Colors.red),
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

            final ticket = state.ticket;
            if (ticket == null) {
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
                    const SizedBox(height: 24),
                    Breakpoints.constrain(
                      TicketCard(ticket: ticket)
                          .animate()
                          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad)
                          .fadeIn(),
                      maxWidth: Breakpoints.isTablet(context)
                          ? 920
                          : Breakpoints.maxCardWidth,
                    ),
                    if (state.pendingListing != null) ...[
                      const SizedBox(height: 16),
                      Breakpoints.constrain(
                        TicketPendingOfferBanner(
                            listing: state.pendingListing!),
                        maxWidth: Breakpoints.maxCardWidth,
                      ),
                    ],
                    if (state.pendingRefundRequest != null) ...[
                      const SizedBox(height: 16),
                      Breakpoints.constrain(
                        TicketPendingRefundBanner(
                            request: state.pendingRefundRequest!),
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
}

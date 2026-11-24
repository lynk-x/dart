import 'package:material_ui/material_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/core/network/lynk_cache_manager.dart';
import 'package:lynk_x/core/utils/breakpoints.dart';
import 'package:lynk_x/core/utils/image_optimizer.dart';
import 'package:lynk_x/core/utils/timezone_abbreviation.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';
import 'package:lynk_x/presentation/features/ticket/screens/ticket_screen_widgets.dart';
import 'package:lynk_x/presentation/features/ticket/widgets/ticket_barcode.dart';

/// Card widget rendering either a standard mobile pass or widescreen boarding pass.
class TicketCard extends StatelessWidget {
  final TicketModel ticket;

  const TicketCard({
    super.key,
    required this.ticket,
  });

  /// Maps ticket.status (active | used | cancelled | expired | transferred)
  /// to a display color and label. isRedeemed (status == 'used') takes
  /// priority over the raw status per the existing REDEEMED-label behavior.
  static (Color, String) statusDisplay(
      TicketModel ticket, BuildContext context) {
    if (ticket.isRedeemed) {
      return (AppColors.secondaryText.withValues(alpha: 0.6), 'REDEEMED');
    }
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

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isTablet(context)) {
      return _buildWidescreenBoardingPass(context);
    }
    return _buildMobileCard(context);
  }

  Widget _buildMobileCard(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final timeFormat = DateFormat('h:mm a');
    final tzAbbr = TimezoneAbbreviation.forIana(ticket.timezone);
    final (statusColor, statusLabel) = statusDisplay(ticket, context);

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

          // Barcode Section with TOTP
          TicketBarcodeSection(
            ticket: ticket,
            height: 60,
          ),
        ],
      ),
    );
  }

  Widget _buildWidescreenBoardingPass(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final timeFormat = DateFormat('h:mm a');
    final tzAbbr = TimezoneAbbreviation.forIana(ticket.timezone);
    final (statusColor, statusLabel) = statusDisplay(ticket, context);

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
                                  border: Border.all(
                                      color: statusColor, width: 1.5),
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

              // Right Stub: Barcode & Code (36% width)
              Expanded(
                flex: 36,
                child: TicketBarcodeSection(
                  ticket: ticket,
                  height: 95,
                  isWidescreen: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

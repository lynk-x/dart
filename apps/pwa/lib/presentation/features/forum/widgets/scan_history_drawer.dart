import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../cubit/ticket_validation_state.dart';

class ScanHistoryDrawer extends StatelessWidget {
  final List<ScanHistoryItem> history;
  final VoidCallback onClearHistory;

  const ScanHistoryDrawer({
    super.key,
    required this.history,
    required this.onClearHistory,
  });

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: (MediaQuery.of(context).size.width * 0.85).clamp(280, 320),
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(40)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SCAN HISTORY (${history.length})',
              style: AppTypography.interTight(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Text(
                        'No tickets scanned yet.',
                        style: AppTypography.inter(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final isSuccess = item.status == ScanStatus.success;
                        final isAlready = item.status == ScanStatus.alreadyScanned;

                        final Color statusColor = isSuccess
                            ? const Color(0xFF2E7D32)
                            : (isAlready ? Colors.orange : Colors.redAccent);

                        final String titleText = isSuccess
                            ? (item.attendeeName ?? 'Attendee')
                            : (isAlready
                                ? '${item.attendeeName ?? 'Attendee'} (Already Scanned)'
                                : 'Failed Validation');

                        final String subtitleText = isSuccess
                            ? 'Code: ${item.code}'
                            : (isAlready
                                ? 'Code: ${item.code}'
                                : (item.errorMessage ?? 'Invalid ticket code'));

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      titleText,
                                      style: AppTypography.interTight(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatTime(item.timestamp),
                                    style: AppTypography.inter(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitleText,
                                style: AppTypography.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (history.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: TextButton.icon(
                  onPressed: onClearHistory,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                  label: Text(
                    'Clear Scan History',
                    style: AppTypography.inter(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

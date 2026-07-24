import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';

/// Client-side grouping of `notification_types` categories — the schema
/// doesn't carry a group column, so this mirrors the taxonomy documented in
/// supabase/seed/05_comms.sql. Any category not listed here (e.g. a type
/// added later without a matching UI update) falls into "Other" rather than
/// being silently dropped from the screen.
const Map<String, String> _categoryGroups = {
  'mention': 'Activity',
  'forum_update': 'Activity',
  'forum_announcement': 'Activity',
  'invitation': 'Activity',
  'event_update': 'Events & Tickets',
  'event_reminder': 'Events & Tickets',
  'event_cancelled': 'Events & Tickets',
  'ticket_purchased': 'Events & Tickets',
  'ticket_cancelled': 'Events & Tickets',
  'ticket_transferred': 'Events & Tickets',
  'ticket_resale_offer': 'Events & Tickets',
  'money_in': 'Money',
  'money_out': 'Money',
  'payout_approved': 'Money',
  'payout_rejected': 'Money',
  'refund_approved': 'Money',
  'refund_rejected': 'Money',
  'marketing': 'Marketing',
  'campaign_budget_alert': 'Marketing',
  'system': 'System',
  'announcements': 'System',
  'identity': 'System',
  'account_suspended': 'System',
  'account_role_changed': 'System',
  'subscription_update': 'System',
  'moderation': 'System',
};

const List<String> _groupOrder = [
  'Activity',
  'Events & Tickets',
  'Money',
  'Marketing',
  'System',
  'Other',
];

class NotificationPreferencesScreen extends StatelessWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          NotificationPreferencesCubit(notificationPreferencesRepository)..load(),
      child: const _NotificationPreferencesView(),
    );
  }
}

class _NotificationPreferencesView extends StatelessWidget {
  const _NotificationPreferencesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notification Preferences',
          style: AppTypography.interTight(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocConsumer<NotificationPreferencesCubit, NotificationPreferencesState>(
        listener: (context, state) {
          if (state is NotificationPreferencesLoaded && state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!), backgroundColor: Colors.redAccent),
            );
          }
        },
        builder: (context, state) {
          if (state is NotificationPreferencesLoading || state is NotificationPreferencesInitial) {
            return Center(child: CircularProgressIndicator(color: context.accentColor));
          }

          if (state is NotificationPreferencesError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          final items = (state as NotificationPreferencesLoaded).items;
          final grouped = <String, List<NotificationPreferenceItem>>{};
          for (final item in items) {
            final group = _categoryGroups[item.category.id] ?? 'Other';
            grouped.putIfAbsent(group, () => []).add(item);
          }

          final orderedGroups = _groupOrder.where((g) => grouped.containsKey(g));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Choose how you want to hear about each kind of activity. In-app notifications always show in your notification list regardless of these settings.',
                    style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                  ),
                ),
                for (final group in orderedGroups) ...[
                  _buildSectionHeader(context, group),
                  for (final item in grouped[group]!)
                    _PreferenceCard(
                      item: item,
                      isSaving: state.savingType == item.category.id,
                    ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  final NotificationPreferenceItem item;
  final bool isSaving;

  const _PreferenceCard({required this.item, required this.isSaving});

  @override
  Widget build(BuildContext context) {
    final category = item.category;
    final preference = item.preference;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.displayName,
                  style: AppTypography.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isSaving)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.accentColor,
                  ),
                ),
            ],
          ),
          if (category.description != null) ...[
            const SizedBox(height: 2),
            Text(
              category.description!,
              style: AppTypography.inter(fontSize: 12, color: Colors.white38),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _ChannelToggle(
                label: 'In-App',
                value: preference.inApp,
                onChanged: isSaving
                    ? null
                    : (v) => context
                        .read<NotificationPreferencesCubit>()
                        .updatePreference(category.id, inApp: v),
              ),
              const SizedBox(width: 20),
              _ChannelToggle(
                label: 'Push',
                value: preference.push,
                onChanged: isSaving
                    ? null
                    : (v) => context
                        .read<NotificationPreferencesCubit>()
                        .updatePreference(category.id, push: v),
              ),
              const SizedBox(width: 20),
              _ChannelToggle(
                label: 'Email',
                value: preference.email,
                onChanged: isSaving
                    ? null
                    : (v) => context
                        .read<NotificationPreferencesCubit>()
                        .updatePreference(category.id, email: v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ChannelToggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 20,
            child: Transform.scale(
              scale: 0.75,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: context.accentColor,
                activeThumbColor: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.inter(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

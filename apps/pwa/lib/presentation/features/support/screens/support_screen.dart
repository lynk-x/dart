import 'package:material_ui/material_ui.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/support/screens/live_chat_screen.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// Support hub screen — active tickets, FAQs, and entry into live chat.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late Future<List<Map<String, dynamic>>> _activeTicketsFuture;
  bool _isLoadingChat = false;

  static const List<Map<String, String>> _faqs = [
    {
      'q': 'How do I buy tickets for an event?',
      'a': 'Browse the event listing, select your ticket type and quantity, then checkout. Your ticket will appear in "My Tickets" immediately after payment.',
    },
    {
      'q': 'Can I transfer my ticket to someone else?',
      'a': 'Yes. Go to the ticket details page, tap "Transfer", and enter the recipient\'s Lynk-X username. Some events disable transfers within 24 hours of the start time.',
    },
    {
      'q': 'How do I request a refund?',
      'a': 'Refund policies are set by the event organizer. You can generally request a refund up to 72 hours before the event via the ticket details page.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    setState(() {
      _activeTicketsFuture = userId != null
          ? supportRepository.getActiveTickets(userId, 'general')
          : Future.value([]);
    });
  }

  Future<void> _startLiveChat() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      AppSnackBars.showError(context, 'Please log in first');
      return;
    }

    setState(() => _isLoadingChat = true);
    try {
      final ticketId = await supportRepository.createTicket(
          userId,
          'general',
          'New Support Request',
          'I need help with my account.');
      if (mounted) {
        context.push('/support/chat?ticketId=$ticketId').then((_) => _loadData());
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showError(context, 'Failed to start chat: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoadingChat = false);
    }
  }

  Future<void> _callSupport() async {
    // Since we don't have a live phone number yet, we gracefully inform the user
    // and route them to our primary support channel (Live Chat).
    if (mounted) {
      AppSnackBars.showInfo(
        context,
        'Phone support is currently offline. Please use Live Chat!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Support',
          style: AppTypography.inter(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Contact
            _buildSectionHeader('Contact Us'),
            _buildActionCard(
              context,
              icon: Icons.chat_bubble_outline_rounded,
              title: _isLoadingChat ? 'Starting Chat...' : 'Live Chat',
              subtitle: 'Wait time: ~2 mins',
              color: context.accentColor,
              onTap: _isLoadingChat ? () {} : _startLiveChat,
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context,
              icon: Icons.phone_in_talk_outlined,
              title: 'Call Support',
              subtitle: '24/7 for urgent issues',
              color: Colors.white,
              onTap: _callSupport,
            ),

            const SizedBox(height: 32),

            // Active Tickets
            _buildSectionHeader('Your Active Tickets'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _activeTicketsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(context.accentColor)),
                    ),
                  );
                }
                final tickets = snapshot.data ?? [];
                if (tickets.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('No active tickets.',
                        style: AppTypography.inter(color: Colors.white54)),
                  );
                }
                return Column(
                  children: tickets.map((t) => _buildTicketTile(t)).toList(),
                );
              },
            ),

            const SizedBox(height: 32),
            _buildSectionHeader('Frequently Asked Questions'),
            Column(
              children: _faqs
                  .map((faq) => _buildFaqTile(
                        context,
                        question: faq['q']!,
                        answer: faq['a']!,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: AppTypography.inter(
                          fontSize: 13, color: Colors.white54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == 'new') return Colors.blue;
    if (status == 'waiting_on_user') return Colors.orange;
    if (status == 'resolved') return Colors.green;
    return Colors.white;
  }

  Widget _buildTicketTile(Map<String, dynamic> ticket) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => LiveChatScreen(ticketId: ticket['id'])),
          ).then((_) => _loadData());
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ticket['reference'] ?? 'Ticket',
                    style: AppTypography.inter(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(ticket['status'])
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (ticket['status'] as String? ?? 'OPEN').toUpperCase(),
                      style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(ticket['status'])),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket['subject'] ?? '',
                style: AppTypography.inter(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaqTile(BuildContext context,
      {required String question, required String answer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Colors.white54,
          collapsedIconColor: Colors.white54,
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              question,
              style: AppTypography.inter(
                  fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          childrenPadding:
              const EdgeInsets.only(left: 80, right: 16, bottom: 16),
          children: [
            Text(
              answer,
              style: AppTypography.inter(
                  fontSize: 13, color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

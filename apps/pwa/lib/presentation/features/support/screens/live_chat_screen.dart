import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/support/screens/support_screen.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveChatScreen extends StatefulWidget {
  final SupportContext supportContext;
  final String? ticketId;
  
  const LiveChatScreen({
    super.key,
    this.supportContext = SupportContext.general,
    this.ticketId,
  });

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen> {
  final TextEditingController _controller = TextEditingController();
  late List<Map<String, dynamic>> _mockMessages;
  final String _currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _mockMessages = [
      {
        'isMe': false,
        'text': 'Hi! I am the Lynk-X Support Assistant. How can I help you today?',
        'time': '10:00 AM'
      },
      if (widget.supportContext == SupportContext.wallet) ...[
        {
          'isMe': true,
          'text': 'My 50,000 KES M-Pesa top-up hasn\'t reflected yet.',
          'time': '10:01 AM'
        },
        {
          'isMe': false,
          'text': 'I apologize for the delay. Let me check your account...',
          'time': '10:01 AM'
        },
        {
          'isMe': false,
          'text': 'I can see the M-Pesa transaction is currently pending network clearance. It should reflect in your wallet within the next 5-10 minutes. Is there anything else I can assist you with?',
          'time': '10:02 AM'
        },
      ] else if (widget.supportContext == SupportContext.events) ...[
        {
          'isMe': true,
          'text': 'I bought a ticket for Afrofest but can\'t see the QR code.',
          'time': '10:01 AM'
        },
        {
          'isMe': false,
          'text': 'Let me check your ticket inventory...',
          'time': '10:01 AM'
        },
        {
          'isMe': false,
          'text': 'Your transaction was successful, but the QR generation is slightly delayed due to high demand. I have manually triggered it for you. Please pull to refresh your "My Tickets" tab.',
          'time': '10:02 AM'
        },
      ] else ...[
        {
          'isMe': true,
          'text': 'How long does account verification take?',
          'time': '10:01 AM'
        },
        {
          'isMe': false,
          'text': 'Standard KYC verification typically takes 1-2 business days. Would you like me to check the status of your specific application?',
          'time': '10:02 AM'
        },
      ]
    ];
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    _controller.clear();
    FocusScope.of(context).unfocus();

    if (widget.ticketId != null) {
      // Send real message to backend
      try {
        await supportRepository.sendMessage(widget.ticketId!, _currentUserId, text);
      } catch (e) {
        // Simple error handling for UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send message: $e')),
          );
        }
      }
    } else {
      // Mock logic
      setState(() {
        _mockMessages.add({
          'isMe': true,
          'text': text,
          'time': 'Now'
        });
      });
      
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _mockMessages.add({
              'isMe': false,
              'text': 'An agent will be with you shortly to assist with this.',
              'time': 'Now'
            });
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 16,
              child: Icon(Icons.support_agent, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lynk-X Support',
                  style: AppTypography.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'Typically replies in 2 mins',
                  style: AppTypography.inter(fontSize: 12, color: Colors.greenAccent),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.ticketId != null
                ? _buildRealtimeMessages()
                : _buildMockMessages(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildRealtimeMessages() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supportRepository.streamMessages(widget.ticketId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading messages', style: TextStyle(color: Colors.white54)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final messages = snapshot.data!;
        
        if (messages.isEmpty) {
          return Center(
            child: Text(
              'No messages yet.\nStart the conversation!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final reversedMessages = messages.reversed.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          reverse: true,
          itemCount: reversedMessages.length,
          itemBuilder: (context, index) {
            final msg = reversedMessages[index];
            final isMe = msg['sender_id'] == _currentUserId;
            
            // Format time simply for showcase
            final timeStr = 'Now'; 
            
            return _buildMessageBubble(
              text: msg['message'] as String? ?? '',
              time: timeStr,
              isMe: isMe,
            );
          },
        );
      },
    );
  }

  Widget _buildMockMessages() {
    final reversedMock = _mockMessages.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      reverse: true,
      itemCount: reversedMock.length,
      itemBuilder: (context, index) {
        final msg = reversedMock[index];
        final isMe = msg['isMe'] as bool;
        
        return _buildMessageBubble(
          text: msg['text'] as String,
          time: msg['time'] as String,
          isMe: isMe,
        );
      },
    );
  }

  Widget _buildMessageBubble({required String text, required String time, required bool isMe}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 12,
                  child: Icon(Icons.support_agent, color: Colors.black, size: 14),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? context.accentColor : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    text,
                    style: AppTypography.inter(
                      fontSize: 14,
                      color: isMe ? Colors.black : Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                const Icon(Icons.done_all, color: Colors.white38, size: 16),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : 32,
              right: isMe ? 24 : 0,
            ),
            child: Text(
              time,
              style: AppTypography.inter(fontSize: 10, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: Colors.white54),
              onPressed: () {},
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.primaryBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: context.accentColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

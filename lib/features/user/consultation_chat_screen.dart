
import 'package:flutter/material.dart';

import '../../models/consultation_message.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';

class ConsultationChatScreen extends StatefulWidget {
    final String appointmentId;

    const ConsultationChatScreen({
        super.key,
        required this.appointmentId,
    });

    @override
    State<ConsultationChatScreen> createState() =>
        _ConsultationChatScreenState();
}

class _ConsultationChatScreenState extends State<ConsultationChatScreen> {
    final ClinicService _service = ClinicService();
    final AuthService _auth = AuthService();
    final TextEditingController _messageController =
        TextEditingController();
    final ScrollController _scrollController = ScrollController();

    bool _sending = false;

    Future<void> _sendMessage() async {
        final text = _messageController.text.trim();

        if (text.isEmpty || _sending) return;

        setState(() {
            _sending = true;
        });

        try {
            await _service.sendConsultationMessage(
                widget.appointmentId,
                text,
            );

            _messageController.clear();
        } catch (e) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to send message: $e'),
                    ),
                );
            }
        } finally {
            if (mounted) {
                setState(() {
                    _sending = false;
                });
            }
        }
    }

    String _formatTime(DateTime dateTime) {
        final hour = dateTime.hour % 12 == 0
            ? 12
            : dateTime.hour % 12;

        final minute = dateTime.minute.toString().padLeft(2, '0');
        final period = dateTime.hour >= 12 ? 'PM' : 'AM';

        return '$hour:$minute $period';
    }

    Widget _buildMessageBubble(
        ConsultationMessage message,
        String currentUserId,
    ) {
        final isMine = message.senderId == currentUserId;

        return Align(
            alignment: isMine
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                ),
                decoration: BoxDecoration(
                    color: isMine
                        ? const Color(0xFF2563EB)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                        Text(
                            message.text,
                            style: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 14,
                            ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                            _formatTime(message.createdAt),
                            style: TextStyle(
                                color: isMine
                                    ? Colors.white70
                                    : Colors.black54,
                                fontSize: 10,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    @override
    void dispose() {
        _messageController.dispose();
        _scrollController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        final currentUserId = _auth.currentUser?.id ?? '';

        return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
                title: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                            'Consultation Chat',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                            ),
                        ),
                        Text(
                            'Private appointment conversation',
                            style: TextStyle(fontSize: 11),
                        ),
                    ],
                ),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E293B),
                elevation: 1,
            ),
            body: Column(
                children: [
                    Expanded(
                        child: StreamBuilder<List<ConsultationMessage>>(
                            stream: _service.consultationMessages(
                                widget.appointmentId,
                            ),
                            builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                    return const Center(
                                        child: Text(
                                            'Unable to load messages.',
                                        ),
                                    );
                                }

                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                    return const Center(
                                        child: CircularProgressIndicator(),
                                    );
                                }

                                final messages = snapshot.data ?? [];

                                WidgetsBinding.instance.addPostFrameCallback((_){
                                  if (_scrollController.hasClients) {
                                    _scrollController.animateTo(
                                      _scrollController.position.maxScrollExtent,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                });

                                if (messages.isEmpty) {
                                    return const Center(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                                Icon(
                                                    Icons.chat_bubble_outline,
                                                    size: 48,
                                                    color: Colors.grey,
                                                ),
                                                SizedBox(height: 12),
                                                Text(
                                                    'No messages yet',
                                                    style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                    ),
                                                ),
                                                SizedBox(height: 5),
                                                Text(
                                                    'Start your conversation here.',
                                                    style: TextStyle(
                                                        color: Colors.grey,
                                                    ),
                                                ),
                                            ],
                                        ),
                                    );
                                }

                                return ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                    ),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                        return _buildMessageBubble(
                                            messages[index],
                                            currentUserId,
                                        );
                                    },
                                );
                            },
                        ),
                    ),
                    SafeArea(
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                            ),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                    top: BorderSide(
                                        color: Colors.grey.shade200,
                                    ),
                                ),
                            ),
                            child: Row(
                                children: [
                                    Expanded(
                                        child: TextField(
                                            controller: _messageController,
                                            minLines: 1,
                                            maxLines: 4,
                                            maxLength: 4000,
                                            decoration: InputDecoration(
                                                hintText: 'Type a message...',
                                                counterText: '',
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF1F5F9),
                                                contentPadding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                ),
                                                border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            24,
                                                        ),
                                                    borderSide:
                                                        BorderSide.none,
                                                ),
                                            ),
                                            onSubmitted: (_) =>
                                                _sendMessage(),
                                        ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                        onPressed:
                                            _sending ? null : _sendMessage,
                                        icon: _sending
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                    ),
                                            )
                                            : const Icon(Icons.send),
                                        style: IconButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF2563EB),
                                            foregroundColor: Colors.white,
                                        ),
                                    ),
                                ],
                            ),
                        ),
                    ),
                ],
            ),
        );
    }
}

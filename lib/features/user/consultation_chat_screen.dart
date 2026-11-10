import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/chat_widgets.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/consultation_message.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';

class ConsultationChatScreen extends StatefulWidget {
  final String appointmentId;
  final VoidCallback? onClose;

  const ConsultationChatScreen({
    super.key,
    required this.appointmentId,
    this.onClose,
  });

  @override
  State<ConsultationChatScreen> createState() => _ConsultationChatScreenState();
}

class _ConsultationChatScreenState extends State<ConsultationChatScreen> {
  final ClinicService _service = ClinicService();
  final AuthService _auth = AuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await _service.sendConsultationMessage(widget.appointmentId, text);
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserRole = _auth.profileSessionToken != null
        ? 'doctor'
        : 'patient';
    final embedded = widget.onClose != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: chatAppBar(
        title: 'Consultation Chat',
        subtitle: 'Private appointment conversation',
        showBack: !embedded,
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
        actions: [
          if (embedded)
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close chat',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ConsultationMessage>>(
              stream: _service.consultationMessages(widget.appointmentId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load messages.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                _scrollToEnd();

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        const Text('No messages yet'),
                        const SizedBox(height: 4),
                        Text(
                          'Start your conversation here.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return ChatBubble(
                      text: m.text,
                      time: formatTime(m.createdAt),
                      mine: m.senderRole == currentUserRole,
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          ChatInputBar(
            controller: _messageController,
            sending: _sending,
            onSend: _sendMessage,
            maxLength: 4000,
          ),
        ],
      ),
    );
  }
}

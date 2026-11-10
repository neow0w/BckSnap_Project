import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/message_service.dart';
import '../../models/message.dart';
import '../../core/chat_widgets.dart';

class MessageScreen extends StatefulWidget {
  final String clinicId;

  const MessageScreen({super.key, required this.clinicId});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final _service = MessageService();
  final _bodyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _service.getMyMessages(widget.clinicId);

      if (!mounted) return;

      setState(() {
        _messages = messages;
        _error = null;
        _loading = false;
      });
      _service.markThreadRead(widget.clinicId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load messages. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final body = _bodyCtrl.text.trim();

    if (body.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _service.sendMessage(widget.clinicId, body);

      if (!mounted) return;

      _bodyCtrl.clear();

      await _loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to send message. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: chatAppBar(
        title: 'Contact Clinic',
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/messages'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                setState(() => _loading = true);
                                _loadMessages();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text('No messages yet'),
                          const SizedBox(height: 4),
                          Text(
                            'Send a message to start the conversation.',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMessages,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return ChatBubble(
                            text: message.body,
                            time: timeLabel(message.createdAt),
                            mine: message.fromPatient,
                          );
                        },
                      ),
                    ),
            ),
            if (_error != null && _messages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const Divider(height: 1),
            ChatInputBar(
              controller: _bodyCtrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

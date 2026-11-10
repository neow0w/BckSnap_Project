import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/message.dart';
import '../../services/api_client.dart';
import '../../services/message_service.dart';
import '../../core/chat_widgets.dart';

/// A conversation with one patient: GET + POST /messages/patient/{id}.
/// Also used by "Contact patient for physical visit" in Figure 9.
class PatientChatScreen extends StatefulWidget {
  final String patientId;
  final String clinicId;
  final String? patientName;

  const PatientChatScreen({
    super.key,
    required this.patientId,
    required this.clinicId,
    this.patientName,
  });

  @override
  State<PatientChatScreen> createState() => _PatientChatScreenState();
}

class _PatientChatScreenState extends State<PatientChatScreen> {
  final _service = MessageService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.thread(widget.patientId, widget.clinicId);
      if (!mounted) return;
      setState(() => _messages = list);
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the conversation.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.reply(widget.patientId, widget.clinicId, text);
      _inputCtrl.clear();
      final list = await _service.thread(widget.patientId, widget.clinicId);
      if (!mounted) return;
      setState(() => _messages = list);
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: chatAppBar(
        title: widget.patientName ?? 'Patient #${widget.patientId}',
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/reception'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessages()),
            const Divider(height: 1),
            ChatInputBar(
              controller: _inputCtrl,
              sending: _sending,
              onSend: _send,
              hint: 'Write a reply...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet. Say hello!'));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        return ChatBubble(
          text: m.body,
          time: timeLabel(m.createdAt),
          mine: !m.fromPatient, // clinic on the right
        );
      },
    );
  }
}

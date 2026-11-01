import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/message_service.dart';
import 'staff_web_shell.dart';

/// Receptionist: conversations with patients, list on the left, chat on the right.
class WebMessagesPage extends StatefulWidget {
  const WebMessagesPage({super.key});

  @override
  State<WebMessagesPage> createState() => _WebMessagesPageState();
}

class _WebMessagesPageState extends State<WebMessagesPage> {
  final MessageService _service = MessageService();
  late final Stream<List<InboxItem>> _inbox = _service.inboxStream();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  InboxItem? _selected;
  Stream<List<ChatMessage>>? _thread;
  int _lastCount = 0;
  bool _sending = false;
  String? _error;

  String get _clinicId => AuthService().currentUser?.clinicId ?? '';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _select(InboxItem item) {
    setState(() {
      _selected = item;
      _thread = _service.threadStream(item.patientId, _clinicId);
      _lastCount = 0;
      _error = null;
    });
  }

  Future<void> _send() async {
    final item = _selected;
    final text = _input.text.trim();
    if (item == null || text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.reply(item.patientId, _clinicId, text);
      _input.clear();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _errorText(Object? e) => e is FirebaseException
      ? apiErrorFrom(e).message
      : 'Could not load the messages.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WebPageHeader(
            title: 'Messages',
            subtitle: 'Conversations with patients of your clinic. New messages appear automatically.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  SizedBox(width: 320, child: _inboxList()),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selected == null
                        ? const Center(child: Text('Select a conversation.'))
                        : _chat(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxList() {
    return StreamBuilder<List<InboxItem>>(
      stream: _inbox,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text(_errorText(snap.error)));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No messages yet.'));
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            return ListTile(
              selected: _selected?.patientId == it.patientId,
              leading: CircleAvatar(
                child: Text(
                  it.patientName.isEmpty
                      ? '?'
                      : it.patientName[0].toUpperCase(),
                ),
              ),
              title: Text(it.patientName),
              subtitle: Text(
                it.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: it.lastAt == null
                  ? null
                  : Text(
                      timeLabel(it.lastAt!),
                      style: const TextStyle(fontSize: 11),
                    ),
              onTap: () => _select(it),
            );
          },
        );
      },
    );
  }

  Widget _chat() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(
            _selected!.patientName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _thread,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(_errorText(snap.error)));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final msgs = snap.data!;
              if (msgs.length != _lastCount) {
                _lastCount = msgs.length;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
              }
              if (msgs.isEmpty) {
                return const Center(child: Text('No messages yet.'));
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final mine = !m.fromPatient; // the clinic is on the right
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 480),
                      decoration: BoxDecoration(
                        color: mine
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.body),
                          const SizedBox(height: 4),
                          Text(
                            timeLabel(m.createdAt),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Write a reply...',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

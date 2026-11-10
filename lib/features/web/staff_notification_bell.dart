
import 'package:flutter/material.dart';

import '../../services/staff_notification_service.dart';

class StaffNotificationBell extends StatefulWidget {
  const StaffNotificationBell({super.key});

  @override
  State<StaffNotificationBell> createState() =>
      _StaffNotificationBellState();
}

class _StaffNotificationBellState extends State<StaffNotificationBell> {
  final StaffNotificationService _service =
      StaffNotificationService();

  List<StaffNotification> _notifications = [];
  bool _loading = true;
  String? _error;

  int get _unreadCount =>
      _notifications.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final items = await _service.getNotifications();

      if (!mounted) return;

      setState(() {
        _notifications = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openNotifications() async {
    await _loadNotifications();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text('Notifications'),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () async {
                      await _loadNotifications();
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _error != null
                        ? Text(_error!)
                        : _notifications.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'You have no notifications yet.',
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _notifications.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _notifications[index];

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: item.read
                                          ? Colors.grey.shade200
                                          : Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                      child: Icon(
                                        Icons.event_note_outlined,
                                        color: item.read
                                            ? Colors.grey
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: item.read
                                            ? FontWeight.normal
                                            : FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(item.message),
                                    trailing: item.read
                                        ? null
                                        : const Icon(
                                            Icons.circle,
                                            size: 9,
                                            color: Colors.blue,
                                          ),
                                    onTap: () async {
                                      if (!item.read) {
                                        try {
                                          await _service.markAsRead(
                                            item.id,
                                          );

                                          await _loadNotifications();

                                          setDialogState(() {});
                                        } catch (e) {
                                          if (!context.mounted) return;

                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                e.toString(),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: _openNotifications,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (_unreadCount > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 17,
                  minHeight: 17,
                ),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _unreadCount > 99
                      ? '99+'
                      : '$_unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

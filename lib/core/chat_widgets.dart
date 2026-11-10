import 'package:flutter/material.dart';

import 'theme.dart';

/// Blue chat header from the mockup ("< Dr. Name").
PreferredSizeWidget chatAppBar({
  required String title,
  String? subtitle,
  VoidCallback? onBack,
  bool showBack = true,
  List<Widget> actions = const [],
}) {
  return AppBar(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    centerTitle: false,
    automaticallyImplyLeading: false,
    leading: showBack
        ? BackButton(color: Colors.white, onPressed: onBack)
        : null,
    actionsIconTheme: const IconThemeData(color: Colors.white),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
      ],
    ),
    actions: actions,
  );
}

/// One message bubble. Own messages on the right, the other side on the left.
class ChatBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool mine;
  const ChatBubble({
    super.key,
    required this.text,
    required this.time,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? AppColors.tonal : AppColors.fieldFill,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              time,
              style: const TextStyle(fontSize: 10, color: AppColors.hint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pill-shaped "Enter text..." bar with the round send button.
/// Pass [onAttach] to show the paperclip (left unset, it is hidden).
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final int maxLength;
  final String hint;
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onAttach,
    this.maxLength = 1000,
    this.hint = 'Enter text...',
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (onAttach != null)
                      IconButton(
                        tooltip: 'Attach a photo',
                        onPressed: sending ? null : onAttach,
                        icon: const Icon(
                          Icons.attach_file,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: maxLength,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: hint,
                          counterText: '',
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send message',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
              ),
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

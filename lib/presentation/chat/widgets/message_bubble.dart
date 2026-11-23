import 'package:flutter/material.dart';
import 'package:realtime_chat/core/utils/time_format.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/presentation/widgets/message_status_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  final Message message;
  final bool isMine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background =
        isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final foreground = isMine ? scheme.onPrimaryContainer : scheme.onSurface;
    final meta = foreground.withValues(alpha: 0.7);
    const radius = Radius.circular(18);
    const tail = Radius.circular(4);
    final failed = message.status == MessageStatus.failed;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: isMine ? radius : tail,
          bottomRight: isMine ? tail : radius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.text,
            style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                TimeFormat.hm(message.sentAt),
                style: theme.textTheme.labelSmall?.copyWith(color: meta),
              ),
              if (isMine) ...[
                const SizedBox(width: 4),
                MessageStatusIcon(status: message.status, size: 14, color: meta),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(onTap: failed ? onRetry : null, child: bubble),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  'Not sent. Tap to retry',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

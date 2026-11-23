import 'package:flutter/material.dart';
import 'package:realtime_chat/core/theme/app_theme.dart';
import 'package:realtime_chat/domain/entities/message.dart';

class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.size = 16,
    this.color,
  });

  final MessageStatus status;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.onSurfaceVariant;
    final (icon, tint, label) = switch (status) {
      MessageStatus.sending => (Icons.schedule, base, 'Sending'),
      MessageStatus.sent => (Icons.done, base, 'Sent'),
      MessageStatus.delivered => (Icons.done_all, base, 'Delivered'),
      MessageStatus.read => (Icons.done_all, AppTheme.readReceipt, 'Read'),
      MessageStatus.failed => (Icons.error_outline, scheme.error, 'Not sent'),
    };
    return Icon(icon, size: size, color: tint, semanticLabel: label);
  }
}

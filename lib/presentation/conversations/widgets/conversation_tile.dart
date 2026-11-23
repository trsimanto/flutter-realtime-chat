import 'package:flutter/material.dart';
import 'package:realtime_chat/core/utils/time_format.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/presentation/widgets/message_status_icon.dart';
import 'package:realtime_chat/presentation/widgets/user_avatar.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = conversation.lastMessage;
    final unread = conversation.unreadCount;
    final hasUnread = unread > 0;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final Widget subtitle;
    if (conversation.isPeerTyping) {
      subtitle = Text(
        'typing...',
        style: muted?.copyWith(
          color: scheme.primary,
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (last == null) {
      subtitle = Text(
        conversation.peer.isOnline ? 'Online now' : 'No messages yet',
        style: muted,
      );
    } else {
      subtitle = Row(
        children: [
          if (last.senderId == currentUserId) ...[
            MessageStatusIcon(status: last.status),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              last.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hasUnread
                  ? muted?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    )
                  : muted,
            ),
          ),
        ],
      );
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(user: conversation.peer),
      title: Text(
        conversation.peer.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null)
            Text(
              TimeFormat.short(last.sentAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hasUnread ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          if (hasUnread)
            Badge.count(
              count: unread,
              backgroundColor: scheme.primary,
              textColor: scheme.onPrimary,
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

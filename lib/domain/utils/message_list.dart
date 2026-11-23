import 'package:realtime_chat/domain/entities/message.dart';

/// Helpers for keeping a newest-first message list consistent.
abstract final class MessageList {
  static List<Message> upsert(List<Message> messages, Message incoming) =>
      merge(messages, [incoming]);

  static List<Message> merge(
    List<Message> current,
    Iterable<Message> incoming,
  ) {
    final result = List<Message>.of(current);
    for (final message in incoming) {
      final index = result.indexWhere((m) => m.matches(message));
      if (index == -1) {
        result.add(message);
      } else {
        final status = result[index].status.advanceTo(message.status);
        result[index] = message.copyWith(status: status);
      }
    }
    result.sort(_newestFirst);
    return result;
  }

  static List<Message> updateStatus(
    List<Message> messages,
    Set<String> ids,
    MessageStatus status,
  ) {
    return [
      for (final message in messages)
        ids.contains(message.id)
            ? message.copyWith(status: message.status.advanceTo(status))
            : message,
    ];
  }

  static int _newestFirst(Message a, Message b) => b.sentAt.compareTo(a.sentAt);
}

import 'dart:async';
import 'dart:convert';

import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/data/protocol/json_mappers.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/utils/message_list.dart';

/// Write-through cache of messages, contacts and unread counters.
///
/// Reads are served from memory after the first access, writes update memory
/// synchronously and persist in the background, so callers never observe a
/// stale state between two frames.
class ChatCache {
  ChatCache(
    this._store, {
    required String userId,
    this.maxMessagesPerConversation = 500,
  }) : _prefix = 'chat:$userId:';

  final KeyValueStore _store;
  final String _prefix;
  final int maxMessagesPerConversation;
  final Map<String, List<Message>> _messages = {};

  /// Newest first.
  List<Message> messages(String conversationId) =>
      List.unmodifiable(_load(conversationId));

  Message? latest(String conversationId) {
    final messages = _load(conversationId);
    return messages.isEmpty ? null : messages.first;
  }

  bool contains(String conversationId, String messageId) =>
      _load(conversationId).any((m) => m.id == messageId);

  List<Message> upsert(String conversationId, Iterable<Message> incoming) {
    return _save(
      conversationId,
      MessageList.merge(_load(conversationId), incoming),
    );
  }

  List<Message> updateStatus(
    String conversationId,
    Set<String> ids,
    MessageStatus status,
  ) {
    return _save(
      conversationId,
      MessageList.updateStatus(_load(conversationId), ids, status),
    );
  }

  List<ChatUser> users() {
    final raw = _store.getString('${_prefix}users');
    if (raw == null) return const [];
    try {
      return JsonMappers.users(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  void saveUsers(List<ChatUser> users) {
    _write(
      '${_prefix}users',
      jsonEncode([for (final user in users) JsonMappers.userToJson(user)]),
    );
  }

  Map<String, int> unreadCounts() {
    final raw = _store.getString('${_prefix}unread');
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in map.entries) entry.key: (entry.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  void saveUnreadCounts(Map<String, int> counts) {
    _write('${_prefix}unread', jsonEncode(counts));
  }

  List<Message> _load(String conversationId) {
    return _messages.putIfAbsent(conversationId, () {
      final raw = _store.getString('${_prefix}messages:$conversationId');
      if (raw == null) return <Message>[];
      try {
        return JsonMappers.messages(jsonDecode(raw));
      } catch (_) {
        return <Message>[];
      }
    });
  }

  List<Message> _save(String conversationId, List<Message> messages) {
    final capped = messages.length > maxMessagesPerConversation
        ? messages.sublist(0, maxMessagesPerConversation)
        : messages;
    _messages[conversationId] = capped;
    _write(
      '${_prefix}messages:$conversationId',
      jsonEncode([for (final m in capped) JsonMappers.messageToJson(m)]),
    );
    return capped;
  }

  void _write(String key, String value) {
    unawaited(_store.setString(key, value));
  }
}

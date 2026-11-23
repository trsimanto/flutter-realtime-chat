import 'dart:convert';

import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/data/protocol/json_mappers.dart';
import 'package:realtime_chat/domain/entities/message.dart';

/// Persistent FIFO of messages the server has not acknowledged yet.
///
/// Entries are removed on ack or on a server-side rejection. Anything left is
/// resent after every reconnect; the server deduplicates by client id, so a
/// resend after a lost ack is harmless.
class Outbox {
  Outbox(this._store, {required String userId}) : _key = 'chat:$userId:outbox';

  final KeyValueStore _store;
  final String _key;
  final List<Message> _pending = [];

  List<Message> get pending => List.unmodifiable(_pending);

  bool get isEmpty => _pending.isEmpty;

  void load() {
    final raw = _store.getString(_key);
    _pending.clear();
    if (raw == null) return;
    try {
      _pending.addAll(JsonMappers.messages(jsonDecode(raw)));
    } catch (_) {
      _pending.clear();
    }
  }

  Message? find(String clientId) {
    for (final message in _pending) {
      if (message.clientId == clientId) return message;
    }
    return null;
  }

  Future<void> add(Message message) async {
    _pending
      ..removeWhere((m) => m.clientId == message.clientId)
      ..add(message);
    await _persist();
  }

  Future<void> remove(String clientId) async {
    final before = _pending.length;
    _pending.removeWhere((m) => m.clientId == clientId);
    if (_pending.length != before) await _persist();
  }

  Future<void> _persist() => _store.setString(
        _key,
        jsonEncode([for (final m in _pending) JsonMappers.messageToJson(m)]),
      );
}

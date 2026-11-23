import 'dart:convert';

import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/domain/entities/session.dart';

class SessionStore {
  SessionStore(this._store);

  static const _key = 'session';

  final KeyValueStore _store;

  Session? load() {
    final raw = _store.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final mode = ChatMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => ChatMode.demo,
      );
      return Session(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        mode: mode,
        serverUrl: (json['serverUrl'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Session session) {
    return _store.setString(
      _key,
      jsonEncode({
        'userId': session.userId,
        'displayName': session.displayName,
        'mode': session.mode.name,
        'serverUrl': session.serverUrl,
      }),
    );
  }

  Future<void> clear() => _store.remove(_key);
}

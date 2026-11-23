import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// In-memory WebSocket relay for direct messages.
///
/// It stores history per conversation, acknowledges sends, relays typing and
/// receipts, tracks presence, and hands undelivered messages to a user when
/// they say hello. Everything is lost on restart, which is fine for a demo.
class ChatServer {
  ChatServer({void Function(String message)? log})
      : _log = log ?? ((message) => stdout.writeln(message));

  static const maxTextLength = 4000;
  static const maxPageSize = 50;
  static final _userIdPattern = RegExp(r'^[a-z0-9-]{1,40}$');
  static const _statusRank = {'sent': 0, 'delivered': 1, 'read': 2};

  final void Function(String message) _log;
  final Map<WebSocket, String?> _clients = {};
  final Map<String, _User> _users = {};
  final Map<String, List<_StoredMessage>> _conversations = {};
  final Map<String, _StoredMessage> _byClientId = {};
  HttpServer? _http;
  int _seq = 0;

  int get port => _http?.port ?? 0;

  Future<void> start({InternetAddress? address, int port = 8080}) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _http = server;
    server.listen(_onRequest);
  }

  Future<void> close() async {
    for (final socket in _clients.keys.toList()) {
      await socket.close(WebSocketStatus.goingAway);
    }
    _clients.clear();
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (request.uri.path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('ok');
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 30);
    _clients[socket] = null;
    socket.listen(
      (data) {
        if (data is String) _onFrame(socket, data);
      },
      onDone: () => _onDisconnect(socket),
      onError: (Object _) => _onDisconnect(socket),
      cancelOnError: true,
    );
  }

  void _onFrame(WebSocket socket, String data) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      _error(socket, 'bad_frame', 'Frames must be JSON objects');
      return;
    }

    try {
      _dispatch(socket, frame);
    } on TypeError {
      _error(
        socket,
        'bad_frame',
        'Malformed ${frame['type']} frame',
        clientId: frame['clientId'] is String ? frame['clientId'] as String : null,
      );
    }
  }

  void _dispatch(WebSocket socket, Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type == 'ping') {
      _send(socket, {'type': 'pong'});
      return;
    }
    if (type == 'hello') {
      _onHello(socket, frame);
      return;
    }

    final userId = _clients[socket];
    if (userId == null) {
      _error(
        socket,
        'unauthenticated',
        'Send hello first',
        clientId: frame['clientId'] as String?,
      );
      return;
    }

    switch (type) {
      case 'send':
        _onSend(socket, userId, frame);
      case 'typing':
        _onTyping(userId, frame);
      case 'receipt':
        _onReceipt(userId, frame);
      case 'history':
        _onHistory(socket, userId, frame);
      default:
        _error(socket, 'unknown_type', 'Unknown frame type: $type');
    }
  }

  void _onHello(WebSocket socket, Map<String, dynamic> frame) {
    final userId = frame['userId'] as String;
    final name = (frame['name'] as String?)?.trim();
    if (!_userIdPattern.hasMatch(userId)) {
      _error(socket, 'invalid_user', 'User ids are lowercase letters, digits and dashes');
      return;
    }

    final wasOnline = _isOnline(userId);
    _clients[socket] = userId;
    final user = _users.putIfAbsent(userId, () => _User(userId, name ?? userId));
    if (name != null && name.isNotEmpty) user.name = name;

    final conversations = <Map<String, dynamic>>[];
    final pending = <Map<String, dynamic>>[];
    for (final entry in _conversations.entries) {
      if (!_isMember(entry.key, userId) || entry.value.isEmpty) continue;
      final incoming = entry.value.where((m) => m.recipientId == userId);
      conversations.add({
        'conversationId': entry.key,
        'lastMessage': entry.value.last.toJson(),
        'unreadCount': incoming.where((m) => m.status != 'read').length,
      });
      pending.addAll([
        for (final m in incoming)
          if (m.status == 'sent') m.toJson(),
      ]);
    }

    _send(socket, {
      'type': 'welcome',
      'user': _userJson(user),
      'users': [
        for (final other in _users.values)
          if (other.id != userId) _userJson(other),
      ],
      'conversations': conversations,
      'pending': pending,
    });

    if (!wasOnline) {
      _broadcast({'type': 'presence', 'user': _userJson(user)}, except: userId);
      _log('+ $userId online (${_onlineCount()} connected)');
    }
  }

  void _onSend(WebSocket socket, String userId, Map<String, dynamic> frame) {
    final clientId = frame['clientId'] as String;
    final to = frame['to'] as String;
    final conversationId = frame['conversationId'] as String;
    final text = (frame['text'] as String).trim();

    if (conversationId != directId(userId, to)) {
      _error(socket, 'invalid_conversation', 'Not a member of $conversationId',
          clientId: clientId);
      return;
    }
    if (text.isEmpty || text.length > maxTextLength) {
      _error(socket, 'invalid_message', 'Text must be 1-$maxTextLength characters',
          clientId: clientId);
      return;
    }

    // A resend after a lost ack gets the original message back.
    final key = '$userId/$clientId';
    final existing = _byClientId[key];
    if (existing != null) {
      _send(socket, {'type': 'ack', 'clientId': clientId, 'message': existing.toJson()});
      return;
    }

    final message = _StoredMessage(
      id: 'm${++_seq}',
      clientId: clientId,
      conversationId: conversationId,
      senderId: userId,
      recipientId: to,
      text: text,
      sentAt: DateTime.now(),
    );
    _conversations.putIfAbsent(conversationId, () => []).add(message);
    _byClientId[key] = message;

    _send(socket, {'type': 'ack', 'clientId': clientId, 'message': message.toJson()});
    final relay = {'type': 'message', 'message': message.toJson()};
    _sendToUser(to, relay);
    if (to != userId) _sendToUser(userId, relay, except: socket);
  }

  void _onTyping(String userId, Map<String, dynamic> frame) {
    final to = frame['to'] as String;
    final conversationId = frame['conversationId'] as String;
    if (conversationId != directId(userId, to)) return;
    _sendToUser(to, {
      'type': 'typing',
      'conversationId': conversationId,
      'userId': userId,
      'isTyping': frame['isTyping'] == true,
    });
  }

  void _onReceipt(String userId, Map<String, dynamic> frame) {
    final conversationId = frame['conversationId'] as String;
    final status = frame['status'] as String;
    final rank = _statusRank[status];
    final messages = _conversations[conversationId];
    if (rank == null || rank == 0 || messages == null) return;

    final ids = (frame['messageIds'] as List<dynamic>).cast<String>().toSet();
    final updatedBySender = <String, List<String>>{};
    for (final message in messages) {
      if (!ids.contains(message.id) || message.recipientId != userId) continue;
      if ((_statusRank[message.status] ?? 0) >= rank) continue;
      message.status = status;
      updatedBySender.putIfAbsent(message.senderId, () => []).add(message.id);
    }

    for (final entry in updatedBySender.entries) {
      _sendToUser(entry.key, {
        'type': 'receipt',
        'conversationId': conversationId,
        'userId': userId,
        'messageIds': entry.value,
        'status': status,
      });
    }
  }

  void _onHistory(WebSocket socket, String userId, Map<String, dynamic> frame) {
    final requestId = frame['requestId'] as String;
    final conversationId = frame['conversationId'] as String;
    if (!_isMember(conversationId, userId)) {
      _error(socket, 'invalid_conversation', 'Not a member of $conversationId');
      return;
    }
    final before = frame['before'];
    final requested = (frame['limit'] as num?)?.toInt() ?? 30;
    final limit = requested < 1
        ? 1
        : (requested > maxPageSize ? maxPageSize : requested);
    final all = _conversations[conversationId] ?? const <_StoredMessage>[];
    final older = before is num
        ? all.where((m) => m.sentAt.millisecondsSinceEpoch < before).toList()
        : all;
    final start = older.length > limit ? older.length - limit : 0;

    _send(socket, {
      'type': 'history',
      'requestId': requestId,
      'conversationId': conversationId,
      'messages': [
        for (final m in older.sublist(start).reversed) m.toJson(),
      ],
      'hasMore': start > 0,
    });
  }

  void _onDisconnect(WebSocket socket) {
    final userId = _clients.remove(socket);
    if (userId == null || _isOnline(userId)) return;
    final user = _users[userId];
    if (user == null) return;
    user.lastSeen = DateTime.now();
    _broadcast({'type': 'presence', 'user': _userJson(user)}, except: userId);
    _log('- $userId offline (${_onlineCount()} connected)');
  }

  bool _isOnline(String userId) => _clients.values.contains(userId);

  int _onlineCount() => _clients.values.whereType<String>().toSet().length;

  bool _isMember(String conversationId, String userId) {
    final parts = conversationId.split(':');
    return parts.length == 3 &&
        parts[0] == 'dm' &&
        (parts[1] == userId || parts[2] == userId);
  }

  Map<String, dynamic> _userJson(_User user) => {
        'id': user.id,
        'name': user.name,
        'online': _isOnline(user.id),
        'lastSeen': user.lastSeen?.millisecondsSinceEpoch,
      };

  void _sendToUser(String userId, Map<String, dynamic> frame, {WebSocket? except}) {
    for (final entry in _clients.entries) {
      if (entry.value == userId && entry.key != except) _send(entry.key, frame);
    }
  }

  void _broadcast(Map<String, dynamic> frame, {String? except}) {
    for (final entry in _clients.entries) {
      final id = entry.value;
      if (id != null && id != except) _send(entry.key, frame);
    }
  }

  void _error(WebSocket socket, String code, String message, {String? clientId}) {
    _send(socket, {
      'type': 'error',
      'code': code,
      'message': message,
      'clientId': clientId,
    });
  }

  void _send(WebSocket socket, Map<String, dynamic> frame) {
    if (socket.closeCode != null) return;
    try {
      socket.add(jsonEncode(frame));
    } on StateError {
      // Socket closed between the check and the write.
    }
  }
}

/// Conversation ids are `dm:<a>:<b>` with both user ids sorted.
String directId(String a, String b) {
  final ids = [a, b]..sort();
  return 'dm:${ids[0]}:${ids[1]}';
}

class _User {
  _User(this.id, this.name);

  final String id;
  String name;
  DateTime? lastSeen;
}

class _StoredMessage {
  _StoredMessage({
    required this.id,
    required this.clientId,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String clientId;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String text;
  final DateTime sentAt;
  String status = 'sent';

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'conversationId': conversationId,
        'senderId': senderId,
        'text': text,
        'sentAt': sentAt.millisecondsSinceEpoch,
        'status': status,
      };
}

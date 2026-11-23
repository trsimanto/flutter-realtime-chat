import 'dart:async';

import 'package:realtime_chat/data/connection/connection_manager.dart';
import 'package:realtime_chat/data/local/chat_cache.dart';
import 'package:realtime_chat/data/local/outbox.dart';
import 'package:realtime_chat/data/protocol/client_frame.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/entities/message_page.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required ConnectionManager connection,
    required ChatCache cache,
    required Outbox outbox,
    required this.me,
    this.historyTimeout = const Duration(seconds: 8),
    this.peerTypingTimeout = const Duration(seconds: 6),
  })  : _connection = connection,
        _cache = cache,
        _outbox = outbox;

  @override
  final ChatUser me;
  final Duration historyTimeout;
  final Duration peerTypingTimeout;

  final ConnectionManager _connection;
  final ChatCache _cache;
  final Outbox _outbox;

  final _updates = StreamController<ChatUpdate>.broadcast();
  final _conversations = StreamController<List<Conversation>>.broadcast();
  final Map<String, ChatUser> _users = {};
  final Map<String, int> _unread = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, Completer<HistoryFrame>> _historyRequests = {};
  final List<ReceiptFrame> _queuedReceipts = [];
  final List<StreamSubscription<Object>> _subscriptions = [];
  int _requestSeq = 0;

  /// True once hello has been sent on the current connection. Nothing else
  /// goes out before it, so the server never sees an unauthenticated frame.
  bool _ready = false;

  @override
  Stream<ChatUpdate> get updates => _updates.stream;

  void start() {
    for (final user in _cache.users()) {
      _users[user.id] = user.copyWith(isOnline: false);
    }
    _unread.addAll(_cache.unreadCounts());
    _outbox.load();
    _subscriptions
      ..add(_connection.frames.listen(_onFrame))
      ..add(_connection.changes.listen(_onConnectionChanged));
    _connection.start();
    _publishConversations();
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _failHistoryRequests();
    await _updates.close();
    await _conversations.close();
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield _buildConversations();
    yield* _conversations.stream;
  }

  @override
  ChatUser? userById(String id) => _users[id];

  @override
  Future<List<Message>> cachedMessages(String conversationId) async {
    return _cache.messages(conversationId).take(50).toList();
  }

  @override
  Future<MessagePage> loadHistory(
    String conversationId, {
    DateTime? before,
    int limit = 30,
  }) async {
    if (_ready) {
      final requestId = 'h${++_requestSeq}';
      final completer = Completer<HistoryFrame>();
      _historyRequests[requestId] = completer;
      final sent = _connection.send(
        HistoryRequestFrame(
          requestId: requestId,
          conversationId: conversationId,
          before: before,
          limit: limit,
        ),
      );
      if (sent) {
        HistoryFrame? frame;
        try {
          frame = await completer.future.timeout(historyTimeout);
        } catch (_) {
          frame = null;
        } finally {
          _historyRequests.remove(requestId);
        }
        if (frame != null) {
          return MessagePage(messages: frame.messages, hasMore: frame.hasMore);
        }
      } else {
        _historyRequests.remove(requestId);
      }
    }
    return _cachedPage(conversationId, before: before, limit: limit);
  }

  @override
  Future<void> send(Message message) async {
    final pending = message.copyWith(status: MessageStatus.sending);
    _cache.upsert(pending.conversationId, [pending]);
    await _outbox.add(pending);
    _publishConversations();
    if (_ready) _connection.send(_sendFrameFor(pending));
  }

  @override
  void setTyping(String conversationId, {required bool isTyping}) {
    if (!_ready) return;
    _connection.send(
      TypingFrame(
        conversationId: conversationId,
        to: _peerOf(conversationId),
        isTyping: isTyping,
      ),
    );
  }

  @override
  Future<void> markRead(String conversationId, List<String> messageIds) async {
    if ((_unread[conversationId] ?? 0) != 0) {
      _unread[conversationId] = 0;
      _cache.saveUnreadCounts(_unread);
    }
    if (messageIds.isNotEmpty) {
      _cache.updateStatus(
        conversationId,
        messageIds.toSet(),
        MessageStatus.read,
      );
      _sendReceipt(
        ReceiptFrame(
          conversationId: conversationId,
          to: _peerOf(conversationId),
          messageIds: messageIds,
          status: MessageStatus.read,
        ),
      );
    }
    _publishConversations();
  }

  void _onConnectionChanged(ConnectionSnapshot snapshot) {
    if (!snapshot.isConnected) {
      _ready = false;
      _failHistoryRequests();
      _clearTyping();
      return;
    }
    if (_ready) return;
    _ready = _connection.send(HelloFrame(userId: me.id, name: me.name));
    if (!_ready) return;

    for (final message in _outbox.pending) {
      _connection.send(_sendFrameFor(message));
    }
    final receipts = List<ReceiptFrame>.of(_queuedReceipts);
    _queuedReceipts.clear();
    receipts.forEach(_sendReceipt);
  }

  void _onFrame(ServerFrame frame) {
    switch (frame) {
      case final WelcomeFrame welcome:
        _onWelcome(welcome);
      case final AckFrame ack:
        _onAck(ack);
      case final IncomingMessageFrame incoming:
        _onIncoming(incoming.message);
      case final PeerReceiptFrame receipt:
        _onReceipt(receipt);
      case final PeerTypingFrame typing:
        _onTyping(typing);
      case final PresenceFrame presence:
        _onPresence(presence.user);
      case final HistoryFrame history:
        _onHistory(history);
      case final ErrorFrame error:
        _onError(error);
      case PongFrame() || UnknownServerFrame():
        break;
    }
  }

  void _onWelcome(WelcomeFrame frame) {
    for (final user in frame.users) {
      if (user.id != me.id) _users[user.id] = user;
    }
    _cache.saveUsers(_users.values.toList());

    final statusChanges = <MessagesStatusChanged>[];
    for (final summary in frame.conversations) {
      _unread[summary.conversationId] = summary.unreadCount;
      final last = summary.lastMessage;
      if (last == null) continue;
      _cache.upsert(summary.conversationId, [last]);
      if (last.senderId == me.id) {
        statusChanges.add(
          MessagesStatusChanged(
            conversationId: summary.conversationId,
            messageIds: [last.id],
            status: last.status,
          ),
        );
      }
    }

    final delivered = <String, List<String>>{};
    for (final message in frame.pending) {
      _cache.upsert(message.conversationId, [message]);
      if (message.senderId != me.id) {
        delivered.putIfAbsent(message.conversationId, () => []).add(message.id);
      }
    }
    _cache.saveUnreadCounts(_unread);
    for (final entry in delivered.entries) {
      _sendReceipt(
        ReceiptFrame(
          conversationId: entry.key,
          to: _peerOf(entry.key),
          messageIds: entry.value,
          status: MessageStatus.delivered,
        ),
      );
    }

    for (final user in _users.values) {
      _updates.add(UserPresenceChanged(user));
    }
    statusChanges.forEach(_updates.add);
    for (final message in frame.pending) {
      _updates.add(MessageReceived(message));
    }
    _publishConversations();
  }

  void _onAck(AckFrame frame) {
    unawaited(_outbox.remove(frame.clientId));
    _cache.upsert(frame.message.conversationId, [frame.message]);
    _updates.add(
      MessageAcknowledged(clientId: frame.clientId, message: frame.message),
    );
    _publishConversations();
  }

  void _onIncoming(Message message) {
    final conversationId = message.conversationId;
    final isNew = !_cache.contains(conversationId, message.id);
    _cache.upsert(conversationId, [message]);
    if (message.senderId != me.id) {
      if (isNew) {
        _unread[conversationId] = (_unread[conversationId] ?? 0) + 1;
        _cache.saveUnreadCounts(_unread);
      }
      _typingTimers.remove(conversationId)?.cancel();
      _sendReceipt(
        ReceiptFrame(
          conversationId: conversationId,
          to: message.senderId,
          messageIds: [message.id],
          status: MessageStatus.delivered,
        ),
      );
    }
    _updates.add(MessageReceived(message));
    _publishConversations();
  }

  void _onReceipt(PeerReceiptFrame frame) {
    _cache.updateStatus(
      frame.conversationId,
      frame.messageIds.toSet(),
      frame.status,
    );
    _updates.add(
      MessagesStatusChanged(
        conversationId: frame.conversationId,
        messageIds: frame.messageIds,
        status: frame.status,
      ),
    );
    _publishConversations();
  }

  void _onTyping(PeerTypingFrame frame) {
    if (frame.userId == me.id) return;
    final conversationId = frame.conversationId;
    _typingTimers.remove(conversationId)?.cancel();
    if (frame.isTyping) {
      // Typing indicators expire on their own in case the "stopped" frame
      // never arrives.
      _typingTimers[conversationId] = Timer(peerTypingTimeout, () {
        _typingTimers.remove(conversationId);
        _publishConversations();
      });
    }
    _updates.add(
      PeerTypingChanged(
        conversationId: conversationId,
        userId: frame.userId,
        isTyping: frame.isTyping,
      ),
    );
    _publishConversations();
  }

  void _onPresence(ChatUser user) {
    if (user.id == me.id) return;
    _users[user.id] = user;
    _cache.saveUsers(_users.values.toList());
    _updates.add(UserPresenceChanged(user));
    _publishConversations();
  }

  void _onHistory(HistoryFrame frame) {
    _cache.upsert(frame.conversationId, frame.messages);
    final completer = _historyRequests.remove(frame.requestId);
    if (completer != null && !completer.isCompleted) completer.complete(frame);
  }

  void _onError(ErrorFrame frame) {
    final clientId = frame.clientId;
    if (clientId == null) return;
    final rejected = _outbox.find(clientId);
    if (rejected == null) return;
    unawaited(_outbox.remove(clientId));
    final failed = rejected.copyWith(status: MessageStatus.failed);
    _cache.upsert(failed.conversationId, [failed]);
    _updates.add(
      MessageFailed(
        conversationId: failed.conversationId,
        clientId: clientId,
        reason: frame.message,
      ),
    );
    _publishConversations();
  }

  void _sendReceipt(ReceiptFrame receipt) {
    if (!_ready || !_connection.send(receipt)) _queuedReceipts.add(receipt);
  }

  SendMessageFrame _sendFrameFor(Message message) =>
      SendMessageFrame.fromMessage(message, to: _peerOf(message.conversationId));

  String _peerOf(String conversationId) =>
      ConversationIds.peerOf(conversationId, me.id) ?? me.id;

  MessagePage _cachedPage(
    String conversationId, {
    DateTime? before,
    required int limit,
  }) {
    final all = _cache.messages(conversationId);
    final older = before == null
        ? all
        : all.where((m) => m.sentAt.isBefore(before)).toList();
    return MessagePage(
      messages: older.take(limit).toList(),
      hasMore: older.length > limit,
    );
  }

  void _failHistoryRequests() {
    for (final completer in _historyRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Connection lost'));
      }
    }
    _historyRequests.clear();
  }

  void _clearTyping() {
    if (_typingTimers.isEmpty) return;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _publishConversations();
  }

  void _publishConversations() {
    if (!_conversations.isClosed) _conversations.add(_buildConversations());
  }

  List<Conversation> _buildConversations() {
    final items = [
      for (final user in _users.values)
        if (user.id != me.id) _conversationWith(user),
    ];
    items.sort((a, b) {
      final at = a.lastMessage?.sentAt;
      final bt = b.lastMessage?.sentAt;
      if (at == null && bt == null) {
        return a.peer.name.toLowerCase().compareTo(b.peer.name.toLowerCase());
      }
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return items;
  }

  Conversation _conversationWith(ChatUser user) {
    final id = ConversationIds.direct(me.id, user.id);
    return Conversation(
      id: id,
      peer: user,
      lastMessage: _cache.latest(id),
      unreadCount: _unread[id] ?? 0,
      isPeerTyping: _typingTimers.containsKey(id),
    );
  }
}

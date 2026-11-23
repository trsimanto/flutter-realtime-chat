import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:realtime_chat/data/protocol/client_frame.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/data/socket/chat_socket.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/repositories/network_simulator.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';

class SimulatedNetworkException implements Exception {
  const SimulatedNetworkException(this.message);

  final String message;

  @override
  String toString() => 'SimulatedNetworkException: $message';
}

/// An in-process server that speaks the same JSON protocol as `server/`,
/// populated with a few bot contacts. Used for demo mode so the app is fully
/// usable without running anything else.
class FakeChatSocket implements ChatSocket, NetworkSimulator {
  FakeChatSocket({
    Random? random,
    this.latency = const Duration(milliseconds: 180),
    this.connectDelay = const Duration(milliseconds: 400),
  }) : _random = random ?? Random() {
    for (final bot in _createBots()) {
      _bots[bot.user.id] = bot;
    }
  }

  final Duration latency;
  final Duration connectDelay;
  final Random _random;
  final _events = StreamController<SocketEvent>.broadcast();
  final Set<Timer> _timers = {};
  final Map<String, _Bot> _bots = {};
  final Map<String, List<Message>> _history = {};
  final Map<String, Message> _byClientId = {};
  bool _open = false;
  bool _networkAvailable = true;
  String? _me;
  int _seq = 0;

  @override
  Stream<SocketEvent> get events => _events.stream;

  @override
  bool get isNetworkAvailable => _networkAvailable;

  @override
  void setNetworkAvailable({required bool available}) {
    _networkAvailable = available;
    if (!available && _open) {
      _open = false;
      _events.add(const SocketClosed(SimulatedNetworkException('Network lost')));
    }
  }

  @override
  Future<void> connect(Uri uri) async {
    await Future<void>.delayed(connectDelay);
    if (!_networkAvailable) {
      throw const SimulatedNetworkException('Network unreachable');
    }
    _open = true;
  }

  @override
  void send(String data) {
    if (!_open) throw StateError('Socket is not connected');
    final frame = ClientFrame.fromJson(jsonDecode(data) as Map<String, dynamic>);
    if (frame == null) return;
    _later(latency, () => _handle(frame));
  }

  @override
  Future<void> disconnect() async {
    _open = false;
  }

  @override
  Future<void> dispose() async {
    _open = false;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    await _events.close();
  }

  void _handle(ClientFrame frame) {
    switch (frame) {
      case final HelloFrame hello:
        _onHello(hello);
      case final SendMessageFrame send:
        _onSend(send);
      case final ReceiptFrame receipt:
        _onReceipt(receipt);
      case final HistoryRequestFrame request:
        _onHistory(request);
      case TypingFrame():
        break;
      case PingFrame():
        _emit(const PongFrame());
    }
  }

  void _onHello(HelloFrame frame) {
    final me = frame.userId;
    _me = me;
    if (_history.isEmpty) _seed(me);

    final conversations = <ConversationSummary>[];
    final pending = <Message>[];
    for (final entry in _history.entries) {
      final messages = entry.value;
      if (messages.isEmpty) continue;
      final incoming = messages.where((m) => m.senderId != me);
      conversations.add(
        ConversationSummary(
          conversationId: entry.key,
          lastMessage: messages.last,
          unreadCount:
              incoming.where((m) => m.status != MessageStatus.read).length,
        ),
      );
      pending.addAll(incoming.where((m) => m.status == MessageStatus.sent));
    }

    _emit(
      WelcomeFrame(
        user: ChatUser(id: me, name: frame.name, isOnline: true),
        users: [for (final bot in _bots.values) bot.user],
        conversations: conversations,
        pending: pending,
      ),
    );
  }

  void _onSend(SendMessageFrame frame) {
    final me = _me;
    if (me == null) {
      _emit(
        ErrorFrame(
          code: 'unauthenticated',
          message: 'Send hello first',
          clientId: frame.clientId,
        ),
      );
      return;
    }

    final existing = _byClientId[frame.clientId];
    if (existing != null) {
      _emit(AckFrame(clientId: frame.clientId, message: existing));
      return;
    }

    if (frame.text.trim().toLowerCase() == '/fail') {
      _emit(
        ErrorFrame(
          code: 'rejected',
          message: 'The demo server rejected this message',
          clientId: frame.clientId,
        ),
      );
      return;
    }

    final message = Message(
      id: _nextId(),
      clientId: frame.clientId,
      conversationId: frame.conversationId,
      senderId: me,
      text: frame.text,
      sentAt: clock.now(),
    );
    _history.putIfAbsent(frame.conversationId, () => []).add(message);
    _byClientId[frame.clientId] = message;
    _emit(AckFrame(clientId: frame.clientId, message: message));

    final bot = _bots[frame.to];
    if (bot != null) _respond(bot, frame.conversationId);
  }

  void _onReceipt(ReceiptFrame frame) {
    final messages = _history[frame.conversationId];
    if (messages == null) return;
    final ids = frame.messageIds.toSet();
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (ids.contains(message.id)) {
        messages[i] = message.copyWith(
          status: message.status.advanceTo(frame.status),
        );
      }
    }
  }

  void _onHistory(HistoryRequestFrame frame) {
    final all = _history[frame.conversationId] ?? const <Message>[];
    final before = frame.before;
    final older =
        before == null ? all : all.where((m) => m.sentAt.isBefore(before)).toList();
    final start = max(0, older.length - frame.limit);
    _emit(
      HistoryFrame(
        requestId: frame.requestId,
        conversationId: frame.conversationId,
        messages: older.sublist(start).reversed.toList(),
        hasMore: start > 0,
      ),
    );
  }

  void _respond(_Bot bot, String conversationId) {
    if (!bot.user.isOnline) {
      if (bot.wakeScheduled) return;
      bot.wakeScheduled = true;
      _later(const Duration(seconds: 6), () {
        bot.wakeScheduled = false;
        _setPresence(bot, online: true);
        _respond(bot, conversationId);
      });
      return;
    }

    _later(
      const Duration(milliseconds: 500),
      () => _markFromBot(bot, conversationId, MessageStatus.delivered),
    );
    _later(
      const Duration(milliseconds: 1400),
      () => _markFromBot(bot, conversationId, MessageStatus.read),
    );

    if (bot.replyPending) return;
    bot.replyPending = true;
    _later(const Duration(milliseconds: 1800), () {
      _emit(
        PeerTypingFrame(
          conversationId: conversationId,
          userId: bot.user.id,
          isTyping: true,
        ),
      );
    });
    _later(Duration(milliseconds: 3200 + _random.nextInt(1200)), () {
      bot.replyPending = false;
      _emit(
        PeerTypingFrame(
          conversationId: conversationId,
          userId: bot.user.id,
          isTyping: false,
        ),
      );
      final reply = _message(
        conversationId,
        bot.user.id,
        bot.nextReply(),
        clock.now(),
        MessageStatus.sent,
      );
      _history.putIfAbsent(conversationId, () => []).add(reply);
      _emit(IncomingMessageFrame(reply));
      if (bot.sleepy) {
        _later(
          const Duration(seconds: 30),
          () => _setPresence(bot, online: false),
        );
      }
    });
  }

  void _markFromBot(_Bot bot, String conversationId, MessageStatus status) {
    final me = _me;
    final messages = _history[conversationId];
    if (me == null || messages == null) return;
    final ids = <String>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.senderId == me && message.status.index < status.index) {
        messages[i] = message.copyWith(status: status);
        ids.add(message.id);
      }
    }
    if (ids.isEmpty) return;
    _emit(
      PeerReceiptFrame(
        conversationId: conversationId,
        userId: bot.user.id,
        messageIds: ids,
        status: status,
      ),
    );
  }

  void _setPresence(_Bot bot, {required bool online}) {
    bot.user = bot.user.copyWith(
      isOnline: online,
      lastSeen: online ? null : clock.now(),
    );
    _emit(PresenceFrame(bot.user));
  }

  void _seed(String me) {
    final now = clock.now();

    final ava = ConversationIds.direct(me, 'bot-ava');
    const lines = [
      'Did you get a chance to look at the release notes?',
      'Yes, the reconnect fix looks solid.',
      'The outbox flush on reconnect was the tricky part.',
      'Agreed. Ordering matters there.',
      'Want to pair on the pagination tomorrow?',
      'Sure, after standup works for me.',
      'I pushed the new message bubbles.',
      'Looks great in dark mode too.',
    ];
    for (var i = 0; i < 40; i++) {
      _history.putIfAbsent(ava, () => []).add(
            _message(
              ava,
              i.isEven ? 'bot-ava' : me,
              lines[i % lines.length],
              now.subtract(Duration(hours: 50 - i, minutes: i * 3)),
              MessageStatus.read,
            ),
          );
    }
    _history[ava]!.add(
      _message(
        ava,
        'bot-ava',
        'Hey! Scroll up to load older messages, or say something and I will reply.',
        now.subtract(const Duration(minutes: 2)),
        MessageStatus.sent,
      ),
    );

    final mia = ConversationIds.direct(me, 'bot-mia');
    _history[mia] = [
      _message(mia, me, 'Are we still on for Friday?',
          now.subtract(const Duration(hours: 3)), MessageStatus.read),
      _message(mia, 'bot-mia', 'Yes! Booked a table for 7.',
          now.subtract(const Duration(minutes: 40)), MessageStatus.sent),
      _message(mia, 'bot-mia', 'Try the "Go offline" option in the menu, then send me something.',
          now.subtract(const Duration(minutes: 39)), MessageStatus.sent),
    ];

    final leo = ConversationIds.direct(me, 'bot-leo');
    _history[leo] = [
      _message(leo, 'bot-leo', 'I am mostly offline. Message me and I will show up.',
          now.subtract(const Duration(days: 1)), MessageStatus.read),
    ];
  }

  Message _message(
    String conversationId,
    String senderId,
    String text,
    DateTime sentAt,
    MessageStatus status,
  ) {
    final id = _nextId();
    return Message(
      id: id,
      clientId: id,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      sentAt: sentAt,
      status: status,
    );
  }

  String _nextId() => 'demo_${++_seq}';

  void _emit(ServerFrame frame) {
    if (!_open || _events.isClosed) return;
    _events.add(SocketMessage(jsonEncode(frame.toJson())));
  }

  /// Timers keep running while disconnected, like a real server would; their
  /// results reach the app through the welcome frame on reconnect.
  void _later(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      action();
    });
    _timers.add(timer);
  }

  static List<_Bot> _createBots() {
    final now = clock.now();
    return [
      _Bot(
        user: const ChatUser(id: 'bot-ava', name: 'Ava', isOnline: true),
        replies: const [
          'Got it! Watch the ticks: sent, delivered, then read.',
          'Try "Simulate connection drop" from the menu while typing.',
          'Messages you send offline wait in the outbox and go out on reconnect.',
          'Send "/fail" to see how a rejected message looks.',
          'Nice. Anything else you want to try?',
        ],
      ),
      _Bot(
        user: const ChatUser(id: 'bot-mia', name: 'Mia', isOnline: true),
        replies: const [
          'Sounds good!',
          'Haha, true.',
          'Let me check and get back to you.',
          'See you Friday then.',
        ],
      ),
      _Bot(
        user: ChatUser(
          id: 'bot-leo',
          name: 'Leo',
          lastSeen: now.subtract(const Duration(hours: 2)),
        ),
        sleepy: true,
        replies: const [
          'Sorry, was away. What did I miss?',
          'Back online for a bit.',
        ],
      ),
    ];
  }
}

class _Bot {
  _Bot({required this.user, required this.replies, this.sleepy = false});

  ChatUser user;
  final List<String> replies;
  final bool sleepy;
  bool replyPending = false;
  bool wakeScheduled = false;
  int _next = 0;

  String nextReply() => replies[_next++ % replies.length];
}

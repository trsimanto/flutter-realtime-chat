import 'dart:async';

import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/entities/message_page.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/repositories/connection_monitor.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.me = const ChatUser(id: 'me', name: 'Me')});

  @override
  final ChatUser me;

  final _updates = StreamController<ChatUpdate>.broadcast();
  final List<Message> sent = [];
  final List<bool> typing = [];
  final List<List<String>> readReceipts = [];
  final List<DateTime?> historyRequests = [];

  List<Message> cached = [];
  MessagePage historyPage = const MessagePage(messages: [], hasMore: false);
  Object? sendError;

  void emitUpdate(ChatUpdate update) => _updates.add(update);

  @override
  Stream<ChatUpdate> get updates => _updates.stream;

  @override
  Stream<List<Conversation>> watchConversations() => const Stream.empty();

  @override
  ChatUser? userById(String id) => null;

  @override
  Future<List<Message>> cachedMessages(String conversationId) async => cached;

  @override
  Future<MessagePage> loadHistory(
    String conversationId, {
    DateTime? before,
    int limit = 30,
  }) async {
    historyRequests.add(before);
    return historyPage;
  }

  @override
  Future<void> send(Message message) async {
    sent.add(message);
    final error = sendError;
    if (error != null) throw error;
  }

  @override
  void setTyping(String conversationId, {required bool isTyping}) {
    typing.add(isTyping);
  }

  @override
  Future<void> markRead(String conversationId, List<String> messageIds) async {
    readReceipts.add(messageIds);
  }
}

class FakeConnectionMonitor implements ConnectionMonitor {
  FakeConnectionMonitor([this.current = const ConnectionSnapshot.connected()]);

  @override
  ConnectionSnapshot current;

  @override
  Stream<ConnectionSnapshot> get changes => const Stream.empty();

  @override
  void retryNow() {}

  @override
  void simulateDrop() {}
}

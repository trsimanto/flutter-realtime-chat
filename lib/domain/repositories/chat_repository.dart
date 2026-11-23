import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/entities/message_page.dart';

abstract interface class ChatRepository {
  ChatUser get me;

  Stream<ChatUpdate> get updates;

  /// Emits the current list right away, then on every change.
  Stream<List<Conversation>> watchConversations();

  ChatUser? userById(String id);

  /// Messages from the local cache, newest first.
  Future<List<Message>> cachedMessages(String conversationId);

  /// Loads a page of messages older than [before] (or the latest page).
  /// Falls back to the local cache when the server can't be reached.
  Future<MessagePage> loadHistory(
    String conversationId, {
    DateTime? before,
    int limit = 30,
  });

  /// Queues [message] in the outbox and sends it as soon as possible.
  Future<void> send(Message message);

  void setTyping(String conversationId, {required bool isTyping});

  Future<void> markRead(String conversationId, List<String> messageIds);
}

import 'package:equatable/equatable.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.peer,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPeerTyping = false,
  });

  final String id;
  final ChatUser peer;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPeerTyping;

  @override
  List<Object?> get props => [id, peer, lastMessage, unreadCount, isPeerTyping];
}

import 'package:equatable/equatable.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';

/// Something that happened on the realtime channel and matters to the UI.
sealed class ChatUpdate extends Equatable {
  const ChatUpdate();
}

final class MessageReceived extends ChatUpdate {
  const MessageReceived(this.message);

  final Message message;

  @override
  List<Object?> get props => [message];
}

final class MessageAcknowledged extends ChatUpdate {
  const MessageAcknowledged({required this.clientId, required this.message});

  final String clientId;
  final Message message;

  @override
  List<Object?> get props => [clientId, message];
}

final class MessageFailed extends ChatUpdate {
  const MessageFailed({
    required this.conversationId,
    required this.clientId,
    this.reason = '',
  });

  final String conversationId;
  final String clientId;
  final String reason;

  @override
  List<Object?> get props => [conversationId, clientId, reason];
}

final class MessagesStatusChanged extends ChatUpdate {
  const MessagesStatusChanged({
    required this.conversationId,
    required this.messageIds,
    required this.status,
  });

  final String conversationId;
  final List<String> messageIds;
  final MessageStatus status;

  @override
  List<Object?> get props => [conversationId, messageIds, status];
}

final class PeerTypingChanged extends ChatUpdate {
  const PeerTypingChanged({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
  });

  final String conversationId;
  final String userId;
  final bool isTyping;

  @override
  List<Object?> get props => [conversationId, userId, isTyping];
}

final class UserPresenceChanged extends ChatUpdate {
  const UserPresenceChanged(this.user);

  final ChatUser user;

  @override
  List<Object?> get props => [user];
}

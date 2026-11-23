import 'package:equatable/equatable.dart';
import 'package:realtime_chat/data/protocol/json_mappers.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';

/// Frames sent from the server to the app.
sealed class ServerFrame extends Equatable {
  const ServerFrame();

  Map<String, dynamic> toJson();

  static ServerFrame fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'welcome' => WelcomeFrame(
          user: JsonMappers.user(json['user'] as Map<String, dynamic>),
          users: JsonMappers.users(json['users']),
          conversations: [
            for (final item in (json['conversations'] as List<dynamic>?) ??
                const <dynamic>[])
              ConversationSummary.fromJson(item as Map<String, dynamic>),
          ],
          pending: JsonMappers.messages(json['pending']),
        ),
      'ack' => AckFrame(
          clientId: json['clientId'] as String,
          message: JsonMappers.message(json['message'] as Map<String, dynamic>),
        ),
      'message' => IncomingMessageFrame(
          JsonMappers.message(json['message'] as Map<String, dynamic>),
        ),
      'typing' => PeerTypingFrame(
          conversationId: json['conversationId'] as String,
          userId: json['userId'] as String,
          isTyping: json['isTyping'] == true,
        ),
      'receipt' => PeerReceiptFrame(
          conversationId: json['conversationId'] as String,
          userId: json['userId'] as String,
          messageIds: JsonMappers.strings(json['messageIds']),
          status: MessageStatus.parse(json['status'] as String?),
        ),
      'presence' => PresenceFrame(
          JsonMappers.user(json['user'] as Map<String, dynamic>),
        ),
      'history' => HistoryFrame(
          requestId: json['requestId'] as String,
          conversationId: json['conversationId'] as String,
          messages: JsonMappers.messages(json['messages']),
          hasMore: json['hasMore'] == true,
        ),
      'error' => ErrorFrame(
          code: (json['code'] as String?) ?? 'unknown',
          message: (json['message'] as String?) ?? '',
          clientId: json['clientId'] as String?,
        ),
      'pong' => const PongFrame(),
      _ => UnknownServerFrame(type is String ? type : ''),
    };
  }
}

class ConversationSummary extends Equatable {
  const ConversationSummary({
    required this.conversationId,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'];
    return ConversationSummary(
      conversationId: json['conversationId'] as String,
      lastMessage:
          last is Map<String, dynamic> ? JsonMappers.message(last) : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String conversationId;
  final Message? lastMessage;
  final int unreadCount;

  Map<String, dynamic> toJson() {
    final last = lastMessage;
    return {
      'conversationId': conversationId,
      'lastMessage': last == null ? null : JsonMappers.messageToJson(last),
      'unreadCount': unreadCount,
    };
  }

  @override
  List<Object?> get props => [conversationId, lastMessage, unreadCount];
}

final class WelcomeFrame extends ServerFrame {
  const WelcomeFrame({
    required this.user,
    this.users = const [],
    this.conversations = const [],
    this.pending = const [],
  });

  final ChatUser user;

  /// Everyone else the server knows about.
  final List<ChatUser> users;
  final List<ConversationSummary> conversations;

  /// Messages addressed to this user that no device has received yet.
  final List<Message> pending;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'welcome',
        'user': JsonMappers.userToJson(user),
        'users': [for (final u in users) JsonMappers.userToJson(u)],
        'conversations': [for (final c in conversations) c.toJson()],
        'pending': [for (final m in pending) JsonMappers.messageToJson(m)],
      };

  @override
  List<Object?> get props => [user, users, conversations, pending];
}

final class AckFrame extends ServerFrame {
  const AckFrame({required this.clientId, required this.message});

  final String clientId;
  final Message message;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ack',
        'clientId': clientId,
        'message': JsonMappers.messageToJson(message),
      };

  @override
  List<Object?> get props => [clientId, message];
}

final class IncomingMessageFrame extends ServerFrame {
  const IncomingMessageFrame(this.message);

  final Message message;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'message',
        'message': JsonMappers.messageToJson(message),
      };

  @override
  List<Object?> get props => [message];
}

final class PeerTypingFrame extends ServerFrame {
  const PeerTypingFrame({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
  });

  final String conversationId;
  final String userId;
  final bool isTyping;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'typing',
        'conversationId': conversationId,
        'userId': userId,
        'isTyping': isTyping,
      };

  @override
  List<Object?> get props => [conversationId, userId, isTyping];
}

final class PeerReceiptFrame extends ServerFrame {
  const PeerReceiptFrame({
    required this.conversationId,
    required this.userId,
    required this.messageIds,
    required this.status,
  });

  final String conversationId;
  final String userId;
  final List<String> messageIds;
  final MessageStatus status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'receipt',
        'conversationId': conversationId,
        'userId': userId,
        'messageIds': messageIds,
        'status': status.name,
      };

  @override
  List<Object?> get props => [conversationId, userId, messageIds, status];
}

final class PresenceFrame extends ServerFrame {
  const PresenceFrame(this.user);

  final ChatUser user;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'presence', 'user': JsonMappers.userToJson(user)};

  @override
  List<Object?> get props => [user];
}

final class HistoryFrame extends ServerFrame {
  const HistoryFrame({
    required this.requestId,
    required this.conversationId,
    required this.messages,
    required this.hasMore,
  });

  final String requestId;
  final String conversationId;

  /// Newest first.
  final List<Message> messages;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'history',
        'requestId': requestId,
        'conversationId': conversationId,
        'messages': [for (final m in messages) JsonMappers.messageToJson(m)],
        'hasMore': hasMore,
      };

  @override
  List<Object?> get props => [requestId, conversationId, messages, hasMore];
}

final class ErrorFrame extends ServerFrame {
  const ErrorFrame({required this.code, required this.message, this.clientId});

  final String code;
  final String message;
  final String? clientId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'error',
        'code': code,
        'message': message,
        'clientId': clientId,
      };

  @override
  List<Object?> get props => [code, message, clientId];
}

final class PongFrame extends ServerFrame {
  const PongFrame();

  @override
  Map<String, dynamic> toJson() => {'type': 'pong'};

  @override
  List<Object?> get props => const [];
}

final class UnknownServerFrame extends ServerFrame {
  const UnknownServerFrame(this.type);

  final String type;

  @override
  Map<String, dynamic> toJson() => {'type': type};

  @override
  List<Object?> get props => [type];
}

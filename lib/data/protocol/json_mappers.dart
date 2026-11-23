import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';

/// Wire format for entities shared by frames and the local cache.
/// Timestamps travel as milliseconds since epoch.
abstract final class JsonMappers {
  static Message message(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      clientId: (json['clientId'] as String?) ?? '',
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      text: json['text'] as String,
      sentAt: time(json['sentAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: MessageStatus.parse(json['status'] as String?),
    );
  }

  static Map<String, dynamic> messageToJson(Message message) {
    return {
      'id': message.id,
      'clientId': message.clientId,
      'conversationId': message.conversationId,
      'senderId': message.senderId,
      'text': message.text,
      'sentAt': message.sentAt.millisecondsSinceEpoch,
      'status': message.status.name,
    };
  }

  static ChatUser user(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return ChatUser(
      id: id,
      name: (json['name'] as String?) ?? id,
      isOnline: json['online'] == true,
      lastSeen: time(json['lastSeen']),
    );
  }

  static Map<String, dynamic> userToJson(ChatUser user) {
    return {
      'id': user.id,
      'name': user.name,
      'online': user.isOnline,
      'lastSeen': user.lastSeen?.millisecondsSinceEpoch,
    };
  }

  static List<Message> messages(Object? raw) => [
        if (raw is List)
          for (final item in raw) message(item as Map<String, dynamic>),
      ];

  static List<ChatUser> users(Object? raw) => [
        if (raw is List)
          for (final item in raw) user(item as Map<String, dynamic>),
      ];

  static List<String> strings(Object? raw) => [
        if (raw is List)
          for (final item in raw) item as String,
      ];

  static DateTime? time(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}

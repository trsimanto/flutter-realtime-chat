import 'package:equatable/equatable.dart';
import 'package:realtime_chat/data/protocol/json_mappers.dart';
import 'package:realtime_chat/domain/entities/message.dart';

/// Frames sent from the app to the server.
sealed class ClientFrame extends Equatable {
  const ClientFrame();

  Map<String, dynamic> toJson();

  static ClientFrame? fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'hello' => HelloFrame(
          userId: json['userId'] as String,
          name: json['name'] as String,
        ),
      'send' => SendMessageFrame(
          clientId: json['clientId'] as String,
          conversationId: json['conversationId'] as String,
          to: json['to'] as String,
          text: json['text'] as String,
          sentAt: JsonMappers.time(json['sentAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      'typing' => TypingFrame(
          conversationId: json['conversationId'] as String,
          to: json['to'] as String,
          isTyping: json['isTyping'] == true,
        ),
      'receipt' => ReceiptFrame(
          conversationId: json['conversationId'] as String,
          to: json['to'] as String,
          messageIds: JsonMappers.strings(json['messageIds']),
          status: MessageStatus.parse(json['status'] as String?),
        ),
      'history' => HistoryRequestFrame(
          requestId: json['requestId'] as String,
          conversationId: json['conversationId'] as String,
          before: JsonMappers.time(json['before']),
          limit: (json['limit'] as num?)?.toInt() ?? 30,
        ),
      'ping' => const PingFrame(),
      _ => null,
    };
  }
}

final class HelloFrame extends ClientFrame {
  const HelloFrame({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'hello', 'userId': userId, 'name': name};

  @override
  List<Object?> get props => [userId, name];
}

final class SendMessageFrame extends ClientFrame {
  const SendMessageFrame({
    required this.clientId,
    required this.conversationId,
    required this.to,
    required this.text,
    required this.sentAt,
  });

  factory SendMessageFrame.fromMessage(Message message, {required String to}) {
    return SendMessageFrame(
      clientId: message.clientId,
      conversationId: message.conversationId,
      to: to,
      text: message.text,
      sentAt: message.sentAt,
    );
  }

  final String clientId;
  final String conversationId;
  final String to;
  final String text;
  final DateTime sentAt;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'send',
        'clientId': clientId,
        'conversationId': conversationId,
        'to': to,
        'text': text,
        'sentAt': sentAt.millisecondsSinceEpoch,
      };

  @override
  List<Object?> get props => [clientId, conversationId, to, text, sentAt];
}

final class TypingFrame extends ClientFrame {
  const TypingFrame({
    required this.conversationId,
    required this.to,
    required this.isTyping,
  });

  final String conversationId;
  final String to;
  final bool isTyping;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'typing',
        'conversationId': conversationId,
        'to': to,
        'isTyping': isTyping,
      };

  @override
  List<Object?> get props => [conversationId, to, isTyping];
}

final class ReceiptFrame extends ClientFrame {
  const ReceiptFrame({
    required this.conversationId,
    required this.to,
    required this.messageIds,
    required this.status,
  });

  final String conversationId;
  final String to;
  final List<String> messageIds;

  /// Either [MessageStatus.delivered] or [MessageStatus.read].
  final MessageStatus status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'receipt',
        'conversationId': conversationId,
        'to': to,
        'messageIds': messageIds,
        'status': status.name,
      };

  @override
  List<Object?> get props => [conversationId, to, messageIds, status];
}

final class HistoryRequestFrame extends ClientFrame {
  const HistoryRequestFrame({
    required this.requestId,
    required this.conversationId,
    this.before,
    this.limit = 30,
  });

  final String requestId;
  final String conversationId;
  final DateTime? before;
  final int limit;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'history',
        'requestId': requestId,
        'conversationId': conversationId,
        'before': before?.millisecondsSinceEpoch,
        'limit': limit,
      };

  @override
  List<Object?> get props => [requestId, conversationId, before, limit];
}

final class PingFrame extends ClientFrame {
  const PingFrame();

  @override
  Map<String, dynamic> toJson() => {'type': 'ping'};

  @override
  List<Object?> get props => const [];
}

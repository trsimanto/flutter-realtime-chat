import 'package:equatable/equatable.dart';

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  /// Statuses only move forward. A failed message can be retried, and a
  /// pending one can still fail.
  MessageStatus advanceTo(MessageStatus next) {
    if (next == MessageStatus.failed || this == MessageStatus.failed) {
      return next;
    }
    return next.index > index ? next : this;
  }

  static MessageStatus parse(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return MessageStatus.sent;
  }
}

class Message extends Equatable {
  const Message({
    required this.id,
    required this.clientId,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.status = MessageStatus.sent,
  });

  /// Server id once acknowledged, otherwise the same value as [clientId].
  final String id;
  final String clientId;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final MessageStatus status;

  bool matches(Message other) =>
      id == other.id || (clientId.isNotEmpty && clientId == other.clientId);

  Message copyWith({
    String? id,
    String? text,
    DateTime? sentAt,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      clientId: clientId,
      conversationId: conversationId,
      senderId: senderId,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props =>
      [id, clientId, conversationId, senderId, text, sentAt, status];
}

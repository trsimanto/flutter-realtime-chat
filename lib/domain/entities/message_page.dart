import 'package:equatable/equatable.dart';
import 'package:realtime_chat/domain/entities/message.dart';

class MessagePage extends Equatable {
  const MessagePage({required this.messages, required this.hasMore});

  /// Newest first.
  final List<Message> messages;
  final bool hasMore;

  @override
  List<Object?> get props => [messages, hasMore];
}

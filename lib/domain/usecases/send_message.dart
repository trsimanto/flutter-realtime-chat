import 'package:clock/clock.dart';
import 'package:realtime_chat/core/utils/id_generator.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';

class SendMessage {
  SendMessage(this._repository, {IdGenerator? newId})
      : _newId = newId ?? IdGenerators.clientId;

  static const maxLength = 4000;

  final ChatRepository _repository;
  final IdGenerator _newId;

  /// Builds the optimistic message, or returns null if there is nothing to send.
  Message? prepare({required String conversationId, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final id = _newId();
    return Message(
      id: id,
      clientId: id,
      conversationId: conversationId,
      senderId: _repository.me.id,
      text: trimmed.length > maxLength
          ? trimmed.substring(0, maxLength)
          : trimmed,
      sentAt: clock.now(),
      status: MessageStatus.sending,
    );
  }

  Future<void> call(Message message) =>
      _repository.send(message.copyWith(status: MessageStatus.sending));
}

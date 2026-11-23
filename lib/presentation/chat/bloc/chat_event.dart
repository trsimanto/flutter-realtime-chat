part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => const [];
}

final class ChatStarted extends ChatEvent {
  const ChatStarted();
}

final class ChatMessageSent extends ChatEvent {
  const ChatMessageSent(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

final class ChatRetryRequested extends ChatEvent {
  const ChatRetryRequested(this.clientId);

  final String clientId;

  @override
  List<Object?> get props => [clientId];
}

final class ChatTextChanged extends ChatEvent {
  const ChatTextChanged(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

final class ChatOlderRequested extends ChatEvent {
  const ChatOlderRequested();
}

final class _ChatUpdateReceived extends ChatEvent {
  const _ChatUpdateReceived(this.update);

  final ChatUpdate update;

  @override
  List<Object?> get props => [update];
}

final class _LocalTypingIdle extends ChatEvent {
  const _LocalTypingIdle();
}

final class _PeerTypingExpired extends ChatEvent {
  const _PeerTypingExpired();
}

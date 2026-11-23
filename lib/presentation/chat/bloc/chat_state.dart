part of 'chat_bloc.dart';

enum ChatLoadStatus { initial, loading, ready }

final class ChatState extends Equatable {
  const ChatState({
    required this.conversationId,
    required this.me,
    required this.peer,
    this.messages = const [],
    this.loadStatus = ChatLoadStatus.initial,
    this.isLoadingOlder = false,
    this.hasMore = true,
    this.isPeerTyping = false,
  });

  factory ChatState.initial({required String me, required ChatUser peer}) {
    return ChatState(
      conversationId: ConversationIds.direct(me, peer.id),
      me: me,
      peer: peer,
    );
  }

  final String conversationId;
  final String me;
  final ChatUser peer;

  /// Newest first, which matches a reversed list view.
  final List<Message> messages;
  final ChatLoadStatus loadStatus;
  final bool isLoadingOlder;
  final bool hasMore;
  final bool isPeerTyping;

  ChatState copyWith({
    ChatUser? peer,
    List<Message>? messages,
    ChatLoadStatus? loadStatus,
    bool? isLoadingOlder,
    bool? hasMore,
    bool? isPeerTyping,
  }) {
    return ChatState(
      conversationId: conversationId,
      me: me,
      peer: peer ?? this.peer,
      messages: messages ?? this.messages,
      loadStatus: loadStatus ?? this.loadStatus,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      hasMore: hasMore ?? this.hasMore,
      isPeerTyping: isPeerTyping ?? this.isPeerTyping,
    );
  }

  @override
  List<Object?> get props => [
        conversationId,
        me,
        peer,
        messages,
        loadStatus,
        isLoadingOlder,
        hasMore,
        isPeerTyping,
      ];
}

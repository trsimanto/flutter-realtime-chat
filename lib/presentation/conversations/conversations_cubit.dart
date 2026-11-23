import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';

class ConversationsState extends Equatable {
  const ConversationsState({
    this.conversations = const [],
    this.isLoading = true,
  });

  final List<Conversation> conversations;
  final bool isLoading;

  int get totalUnread =>
      conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  @override
  List<Object?> get props => [conversations, isLoading];
}

class ConversationsCubit extends Cubit<ConversationsState> {
  ConversationsCubit(ChatRepository repository)
      : super(const ConversationsState()) {
    _subscription = repository.watchConversations().listen(
          (conversations) => emit(
            ConversationsState(conversations: conversations, isLoading: false),
          ),
        );
  }

  late final StreamSubscription<List<Conversation>> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}

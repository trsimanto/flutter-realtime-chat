import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/usecases/send_message.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';
import 'package:realtime_chat/domain/utils/message_list.dart';

part 'chat_event.dart';
part 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatRepository repository,
    required SendMessage sendMessage,
    required ChatUser peer,
    this.pageSize = 30,
    this.typingIdleTimeout = const Duration(seconds: 3),
    this.peerTypingTimeout = const Duration(seconds: 6),
  })  : _repository = repository,
        _sendMessage = sendMessage,
        super(
          ChatState.initial(
            me: repository.me.id,
            peer: repository.userById(peer.id) ?? peer,
          ),
        ) {
    on<ChatStarted>(_onStarted);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatRetryRequested>(_onRetryRequested);
    on<ChatTextChanged>(_onTextChanged);
    on<ChatOlderRequested>(_onOlderRequested);
    on<_ChatUpdateReceived>(_onUpdateReceived);
    on<_LocalTypingIdle>((event, emit) => _stopLocalTyping());
    on<_PeerTypingExpired>(
      (event, emit) => emit(state.copyWith(isPeerTyping: false)),
    );

    // Subscribed here rather than on ChatStarted so nothing that arrives
    // while the first page loads is lost.
    _updates = repository.updates
        .where(_concerns)
        .listen((update) => add(_ChatUpdateReceived(update)));
  }

  final int pageSize;
  final Duration typingIdleTimeout;
  final Duration peerTypingTimeout;

  final ChatRepository _repository;
  final SendMessage _sendMessage;
  late final StreamSubscription<ChatUpdate> _updates;
  Timer? _typingIdleTimer;
  Timer? _peerTypingTimer;
  bool _isTyping = false;

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    emit(state.copyWith(loadStatus: ChatLoadStatus.loading));

    final cached = await _repository.cachedMessages(state.conversationId);
    _emitMarkingRead(
      emit,
      MessageList.merge(state.messages, cached),
      loadStatus: ChatLoadStatus.ready,
      alwaysNotify: true,
    );

    final page = await _repository.loadHistory(
      state.conversationId,
      limit: pageSize,
    );
    _emitMarkingRead(
      emit,
      MessageList.merge(state.messages, page.messages),
      hasMore: page.hasMore,
    );
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    final message = _sendMessage.prepare(
      conversationId: state.conversationId,
      text: event.text,
    );
    if (message == null) return;
    _stopLocalTyping();
    emit(state.copyWith(messages: MessageList.upsert(state.messages, message)));
    await _deliver(message, emit);
  }

  Future<void> _onRetryRequested(
    ChatRetryRequested event,
    Emitter<ChatState> emit,
  ) async {
    Message? failed;
    for (final message in state.messages) {
      if (message.clientId == event.clientId &&
          message.status == MessageStatus.failed) {
        failed = message;
        break;
      }
    }
    if (failed == null) return;
    final retry = failed.copyWith(status: MessageStatus.sending);
    emit(state.copyWith(messages: MessageList.upsert(state.messages, retry)));
    await _deliver(retry, emit);
  }

  Future<void> _deliver(Message message, Emitter<ChatState> emit) async {
    try {
      await _sendMessage(message);
    } catch (_) {
      _markFailed(message.clientId, emit);
    }
  }

  void _onTextChanged(ChatTextChanged event, Emitter<ChatState> emit) {
    if (event.text.trim().isEmpty) {
      _stopLocalTyping();
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      _repository.setTyping(state.conversationId, isTyping: true);
    }
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(typingIdleTimeout, () {
      if (!isClosed) add(const _LocalTypingIdle());
    });
  }

  Future<void> _onOlderRequested(
    ChatOlderRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isLoadingOlder || !state.hasMore || state.messages.isEmpty) {
      return;
    }
    emit(state.copyWith(isLoadingOlder: true));
    final page = await _repository.loadHistory(
      state.conversationId,
      before: state.messages.last.sentAt,
      limit: pageSize,
    );
    emit(
      state.copyWith(
        messages: MessageList.merge(state.messages, page.messages),
        hasMore: page.hasMore,
        isLoadingOlder: false,
      ),
    );
  }

  void _onUpdateReceived(_ChatUpdateReceived event, Emitter<ChatState> emit) {
    switch (event.update) {
      case MessageReceived(:final message):
        final merged = MessageList.upsert(state.messages, message);
        if (message.senderId == state.me) {
          emit(state.copyWith(messages: merged));
        } else {
          _peerTypingTimer?.cancel();
          _emitMarkingRead(emit, merged, isPeerTyping: false);
        }
      case MessageAcknowledged(:final message):
        emit(
          state.copyWith(
            messages: MessageList.upsert(state.messages, message),
          ),
        );
      case MessageFailed(:final clientId):
        _markFailed(clientId, emit);
      case MessagesStatusChanged(:final messageIds, :final status):
        emit(
          state.copyWith(
            messages: MessageList.updateStatus(
              state.messages,
              messageIds.toSet(),
              status,
            ),
          ),
        );
      case PeerTypingChanged(:final isTyping):
        _peerTypingTimer?.cancel();
        if (isTyping) {
          _peerTypingTimer = Timer(peerTypingTimeout, () {
            if (!isClosed) add(const _PeerTypingExpired());
          });
        }
        emit(state.copyWith(isPeerTyping: isTyping));
      case UserPresenceChanged(:final user):
        emit(state.copyWith(peer: user));
    }
  }

  /// Emits [messages] with every incoming message marked as read, and tells
  /// the repository so the sender gets a read receipt.
  void _emitMarkingRead(
    Emitter<ChatState> emit,
    List<Message> messages, {
    ChatLoadStatus? loadStatus,
    bool? hasMore,
    bool? isPeerTyping,
    bool alwaysNotify = false,
  }) {
    final unread = [
      for (final message in messages)
        if (message.senderId != state.me &&
            message.status != MessageStatus.read)
          message.id,
    ];
    emit(
      state.copyWith(
        messages: unread.isEmpty
            ? messages
            : MessageList.updateStatus(
                messages,
                unread.toSet(),
                MessageStatus.read,
              ),
        loadStatus: loadStatus,
        hasMore: hasMore,
        isPeerTyping: isPeerTyping,
      ),
    );
    if (unread.isNotEmpty || alwaysNotify) {
      unawaited(_repository.markRead(state.conversationId, unread));
    }
  }

  void _markFailed(String clientId, Emitter<ChatState> emit) {
    final index = state.messages.indexWhere((m) => m.clientId == clientId);
    if (index == -1) return;
    final failed = state.messages[index].copyWith(status: MessageStatus.failed);
    emit(state.copyWith(messages: MessageList.upsert(state.messages, failed)));
  }

  void _stopLocalTyping() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    if (_isTyping) {
      _isTyping = false;
      _repository.setTyping(state.conversationId, isTyping: false);
    }
  }

  bool _concerns(ChatUpdate update) {
    return switch (update) {
      MessageReceived(:final message) =>
        message.conversationId == state.conversationId,
      MessageAcknowledged(:final message) =>
        message.conversationId == state.conversationId,
      MessageFailed(:final conversationId) =>
        conversationId == state.conversationId,
      MessagesStatusChanged(:final conversationId) =>
        conversationId == state.conversationId,
      PeerTypingChanged(:final conversationId, :final userId) =>
        conversationId == state.conversationId && userId != state.me,
      UserPresenceChanged(:final user) => user.id == state.peer.id,
    };
  }

  @override
  Future<void> close() async {
    _peerTypingTimer?.cancel();
    _stopLocalTyping();
    await _updates.cancel();
    return super.close();
  }
}

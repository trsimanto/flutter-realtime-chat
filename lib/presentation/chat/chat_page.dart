import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/core/di/injection.dart';
import 'package:realtime_chat/core/utils/time_format.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/usecases/send_message.dart';
import 'package:realtime_chat/presentation/chat/bloc/chat_bloc.dart';
import 'package:realtime_chat/presentation/chat/widgets/composer.dart';
import 'package:realtime_chat/presentation/chat/widgets/message_bubble.dart';
import 'package:realtime_chat/presentation/chat/widgets/typing_indicator.dart';
import 'package:realtime_chat/presentation/connection/connection_banner.dart';
import 'package:realtime_chat/presentation/widgets/user_avatar.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.peer});

  final ChatUser peer;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(
        repository: getIt<ChatRepository>(),
        sendMessage: getIt<SendMessage>(),
        peer: peer,
      )..add(const ChatStarted()),
      child: const ChatView(),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  /// The list is reversed, so older messages live near maxScrollExtent.
  void _maybeLoadOlder() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      context.read<ChatBloc>().add(const ChatOlderRequested());
    }
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    context.read<ChatBloc>().add(ChatMessageSent(text));
    _text.clear();
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ChatBloc>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (previous, current) =>
              previous.peer != current.peer ||
              previous.isPeerTyping != current.isPeerTyping,
          builder: (context, state) => _ChatTitle(state: state),
        ),
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              listenWhen: (previous, current) =>
                  previous.messages.length != current.messages.length,
              // A short first page may not fill the screen, in which case
              // no scroll event would ever ask for more.
              listener: (context, state) => WidgetsBinding.instance
                  .addPostFrameCallback((_) => _maybeLoadOlder()),
              builder: (context, state) => _MessageList(
                state: state,
                controller: _scroll,
                onRetry: (clientId) => bloc.add(ChatRetryRequested(clientId)),
              ),
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (previous, current) =>
                previous.isPeerTyping != current.isPeerTyping,
            builder: (context, state) => AnimatedSize(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.bottomCenter,
              child: state.isPeerTyping
                  ? TypingIndicator(name: state.peer.name)
                  : const SizedBox(width: double.infinity),
            ),
          ),
          Composer(
            controller: _text,
            onChanged: (text) => bloc.add(ChatTextChanged(text)),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatTitle extends StatelessWidget {
  const _ChatTitle({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = state.peer;
    final String subtitle;
    if (state.isPeerTyping) {
      subtitle = 'typing...';
    } else if (peer.isOnline) {
      subtitle = 'online';
    } else {
      subtitle = TimeFormat.lastSeen(peer.lastSeen);
    }
    final highlight = state.isPeerTyping || peer.isOnline;

    return Row(
      children: [
        UserAvatar(user: peer, radius: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: highlight
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.controller,
    required this.onRetry,
  });

  final ChatState state;
  final ScrollController controller;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    final messages = state.messages;
    if (messages.isEmpty) {
      if (state.loadStatus != ChatLoadStatus.ready) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          'Say hi to ${state.peer.name}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (state.isLoadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final message = messages[index];
        final older = index + 1 < messages.length ? messages[index + 1] : null;
        final showDay =
            older == null || !TimeFormat.isSameDay(older.sentAt, message.sentAt);
        final bubble = MessageBubble(
          key: ValueKey(message.clientId.isEmpty ? message.id : message.clientId),
          message: message,
          isMine: message.senderId == state.me,
          onRetry: message.status == MessageStatus.failed
              ? () => onRetry(message.clientId)
              : null,
        );
        if (!showDay) return bubble;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [_DayDivider(date: message.sentAt), bubble],
        );
      },
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              TimeFormat.day(date),
              style: theme.textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}

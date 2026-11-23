import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/core/di/injection.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/entities/session.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/repositories/connection_monitor.dart';
import 'package:realtime_chat/domain/repositories/network_simulator.dart';
import 'package:realtime_chat/presentation/chat/chat_page.dart';
import 'package:realtime_chat/presentation/connection/connection_banner.dart';
import 'package:realtime_chat/presentation/connection/connection_cubit.dart';
import 'package:realtime_chat/presentation/conversations/conversations_cubit.dart';
import 'package:realtime_chat/presentation/conversations/widgets/conversation_tile.dart';
import 'package:realtime_chat/presentation/session/session_cubit.dart';
import 'package:realtime_chat/presentation/theme/theme_cubit.dart';

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ConversationsCubit(getIt<ChatRepository>()),
        ),
        BlocProvider(
          create: (_) => ConnectionCubit(getIt<ConnectionMonitor>()),
        ),
      ],
      child: _ConversationsView(session: session),
    );
  }
}

class _ConversationsView extends StatelessWidget {
  const _ConversationsView({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modeLabel = session.mode == ChatMode.demo
        ? 'Demo mode'
        : session.serverUri.authority;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chats'),
            Text(
              '${session.displayName} · $modeLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: const [_MenuButton()],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: BlocBuilder<ConversationsCubit, ConversationsState>(
              builder: (context, state) {
                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.conversations.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.builder(
                  itemCount: state.conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = state.conversations[index];
                    return ConversationTile(
                      key: ValueKey(conversation.id),
                      conversation: conversation,
                      currentUserId: session.userId,
                      onTap: () => _openChat(context, conversation),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, Conversation conversation) {
    final connection = context.read<ConnectionCubit>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: connection,
          child: ChatPage(peer: conversation.peer),
        ),
      ),
    );
  }
}

enum _MenuAction { theme, toggleNetwork, dropConnection, signOut }

class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Menu',
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) {
        final themeMode = context.read<ThemeCubit>().state;
        final simulator = getIt.isRegistered<NetworkSimulator>()
            ? getIt<NetworkSimulator>()
            : null;
        return [
          PopupMenuItem(
            value: _MenuAction.theme,
            child: ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text('Theme: ${themeMode.name}'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (simulator != null)
            PopupMenuItem(
              value: _MenuAction.toggleNetwork,
              child: ListTile(
                leading: Icon(
                  simulator.isNetworkAvailable
                      ? Icons.wifi_off_rounded
                      : Icons.wifi_rounded,
                ),
                title: Text(
                  simulator.isNetworkAvailable ? 'Go offline' : 'Go online',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const PopupMenuItem(
            value: _MenuAction.dropConnection,
            child: ListTile(
              leading: Icon(Icons.link_off_rounded),
              title: Text('Simulate connection drop'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: _MenuAction.signOut,
            child: ListTile(
              leading: Icon(Icons.logout_rounded),
              title: Text('Sign out'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ];
      },
    );
  }

  void _onSelected(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.theme:
        context.read<ThemeCubit>().cycle();
      case _MenuAction.toggleNetwork:
        final simulator = getIt<NetworkSimulator>();
        simulator.setNetworkAvailable(
          available: !simulator.isNetworkAvailable,
        );
      case _MenuAction.dropConnection:
        context.read<ConnectionCubit>().simulateDrop();
      case _MenuAction.signOut:
        context.read<SessionCubit>().signOut();
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No contacts yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Sign in with a different name on a second device or emulator '
              'connected to the same server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

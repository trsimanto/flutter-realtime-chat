import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/usecases/send_message.dart';
import 'package:realtime_chat/presentation/chat/bloc/chat_bloc.dart';
import 'package:realtime_chat/presentation/chat/chat_page.dart';
import 'package:realtime_chat/presentation/chat/widgets/message_bubble.dart';
import 'package:realtime_chat/presentation/connection/connection_cubit.dart';

import 'helpers/fake_chat_repository.dart';

const bob = ChatUser(id: 'bob', name: 'Bob', isOnline: true);

Future<void> pumpChat(WidgetTester tester, FakeChatRepository repository) {
  return tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(FakeConnectionMonitor()),
          ),
          BlocProvider(
            create: (_) => ChatBloc(
              repository: repository,
              sendMessage: SendMessage(repository, newId: () => 'c1'),
              peer: bob,
            )..add(const ChatStarted()),
          ),
        ],
        child: const ChatView(),
      ),
    ),
  );
}

void main() {
  testWidgets('sending shows the message at once and then updates its ticks',
      (tester) async {
    final repository = FakeChatRepository();
    await pumpChat(tester, repository);
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('Say hi to Bob'), findsOneWidget);

    final sendButton = find.byKey(const Key('send-button'));
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Hello Bob');
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);

    await tester.tap(sendButton);
    await tester.pump();

    expect(repository.sent.single.text, 'Hello Bob');
    expect(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.text('Hello Bob'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(repository.typing, [true, false]);

    final sent = repository.sent.single;
    repository.emitUpdate(
      MessageAcknowledged(
        clientId: 'c1',
        message: sent.copyWith(id: 'm1', status: MessageStatus.sent),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byIcon(Icons.done), findsOneWidget);

    repository.emitUpdate(
      MessagesStatusChanged(
        conversationId: sent.conversationId,
        messageIds: const ['m1'],
        status: MessageStatus.read,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('shows the typing indicator while the peer types',
      (tester) async {
    final repository = FakeChatRepository();
    await pumpChat(tester, repository);
    await tester.pump();

    repository.emitUpdate(
      const PeerTypingChanged(
        conversationId: 'dm:bob:me',
        userId: 'bob',
        isTyping: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bob is typing...'), findsOneWidget);

    repository.emitUpdate(
      const PeerTypingChanged(
        conversationId: 'dm:bob:me',
        userId: 'bob',
        isTyping: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bob is typing...'), findsNothing);
  });
}

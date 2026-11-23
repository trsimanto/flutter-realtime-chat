import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/entities/message_page.dart';
import 'package:realtime_chat/domain/usecases/send_message.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';
import 'package:realtime_chat/presentation/chat/bloc/chat_bloc.dart';

import '../helpers/fake_chat_repository.dart';

const peer = ChatUser(id: 'bob', name: 'Bob', isOnline: true);
final conversationId = ConversationIds.direct('me', 'bob');
final t0 = DateTime(2026, 3, 1, 12);

Message message(
  String id, {
  String sender = 'me',
  MessageStatus status = MessageStatus.sent,
  DateTime? at,
  String? clientId,
}) {
  return Message(
    id: id,
    clientId: clientId ?? id,
    conversationId: conversationId,
    senderId: sender,
    text: 'text $id',
    sentAt: at ?? t0,
    status: status,
  );
}

Matcher hasSingleMessage({String? id, MessageStatus? status, String? text}) {
  return isA<ChatState>().having(
    (s) => s.messages,
    'messages',
    allOf(
      hasLength(1),
      predicate<List<Message>>((m) => id == null || m.single.id == id, 'id $id'),
      predicate<List<Message>>(
        (m) => status == null || m.single.status == status,
        'status $status',
      ),
      predicate<List<Message>>(
        (m) => text == null || m.single.text == text,
        'text $text',
      ),
    ),
  );
}

void main() {
  late FakeChatRepository repository;

  setUp(() => repository = FakeChatRepository());

  ChatBloc buildBloc({
    Duration typingIdle = const Duration(seconds: 3),
    Duration peerTypingTimeout = const Duration(seconds: 6),
  }) {
    return ChatBloc(
      repository: repository,
      sendMessage: SendMessage(repository, newId: () => 'c1'),
      peer: peer,
      typingIdleTimeout: typingIdle,
      peerTypingTimeout: peerTypingTimeout,
    );
  }

  ChatState readyState(List<Message> messages, {bool hasMore = true}) {
    return ChatState.initial(me: 'me', peer: peer).copyWith(
      messages: messages,
      loadStatus: ChatLoadStatus.ready,
      hasMore: hasMore,
    );
  }

  group('sending', () {
    blocTest<ChatBloc, ChatState>(
      'adds the message optimistically with a sending status',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('  Hello  ')),
      expect: () => [
        hasSingleMessage(id: 'c1', status: MessageStatus.sending, text: 'Hello'),
      ],
      verify: (_) {
        expect(repository.sent.single.clientId, 'c1');
        expect(repository.sent.single.text, 'Hello');
      },
    );

    blocTest<ChatBloc, ChatState>(
      'ignores blank messages',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('   ')),
      expect: () => <ChatState>[],
      verify: (_) => expect(repository.sent, isEmpty),
    );

    blocTest<ChatBloc, ChatState>(
      'swaps the optimistic message for the acknowledged one',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const ChatMessageSent('Hello'));
        await Future<void>.delayed(Duration.zero);
        repository.emitUpdate(
          MessageAcknowledged(
            clientId: 'c1',
            message: message('m1', clientId: 'c1'),
          ),
        );
      },
      expect: () => [
        hasSingleMessage(id: 'c1', status: MessageStatus.sending),
        hasSingleMessage(id: 'm1', status: MessageStatus.sent),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'marks the message as failed when the repository throws',
      setUp: () => repository.sendError = Exception('disk full'),
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('Hello')),
      expect: () => [
        hasSingleMessage(status: MessageStatus.sending),
        hasSingleMessage(status: MessageStatus.failed),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'marks the message as failed when the server rejects it',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const ChatMessageSent('Hello'));
        await Future<void>.delayed(Duration.zero);
        repository.emitUpdate(
          MessageFailed(conversationId: conversationId, clientId: 'c1'),
        );
      },
      expect: () => [
        hasSingleMessage(status: MessageStatus.sending),
        hasSingleMessage(status: MessageStatus.failed),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'retries a failed message',
      build: buildBloc,
      seed: () => readyState([message('c1', status: MessageStatus.failed)]),
      act: (bloc) => bloc.add(const ChatRetryRequested('c1')),
      expect: () => [hasSingleMessage(status: MessageStatus.sending)],
      verify: (_) => expect(repository.sent.single.clientId, 'c1'),
    );
  });

  group('receipts', () {
    blocTest<ChatBloc, ChatState>(
      'advances delivery state from receipts but never moves it back',
      build: buildBloc,
      seed: () => readyState([message('m1')]),
      act: (bloc) async {
        repository.emitUpdate(
          MessagesStatusChanged(
            conversationId: conversationId,
            messageIds: const ['m1'],
            status: MessageStatus.read,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        repository.emitUpdate(
          MessagesStatusChanged(
            conversationId: conversationId,
            messageIds: const ['m1'],
            status: MessageStatus.delivered,
          ),
        );
      },
      expect: () => [hasSingleMessage(status: MessageStatus.read)],
    );

    blocTest<ChatBloc, ChatState>(
      'marks incoming messages as read while the chat is open',
      build: buildBloc,
      seed: () => readyState(const []),
      act: (bloc) => repository.emitUpdate(
        MessageReceived(message('m2', sender: 'bob')),
      ),
      expect: () => [hasSingleMessage(id: 'm2', status: MessageStatus.read)],
      verify: (_) => expect(repository.readReceipts, [
        ['m2'],
      ]),
    );

    blocTest<ChatBloc, ChatState>(
      'ignores updates for other conversations',
      build: buildBloc,
      act: (bloc) => repository.emitUpdate(
        MessageReceived(
          Message(
            id: 'x',
            clientId: 'x',
            conversationId: ConversationIds.direct('me', 'carol'),
            senderId: 'carol',
            text: 'hi',
            sentAt: t0,
          ),
        ),
      ),
      expect: () => <ChatState>[],
    );
  });

  group('typing', () {
    blocTest<ChatBloc, ChatState>(
      'reports typing once and stops after the idle timeout',
      build: () => buildBloc(typingIdle: const Duration(milliseconds: 40)),
      act: (bloc) => bloc
        ..add(const ChatTextChanged('H'))
        ..add(const ChatTextChanged('He')),
      wait: const Duration(milliseconds: 120),
      expect: () => <ChatState>[],
      verify: (_) => expect(repository.typing, [true, false]),
    );

    blocTest<ChatBloc, ChatState>(
      'stops typing as soon as the message is sent',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ChatTextChanged('Hi'))
        ..add(const ChatMessageSent('Hi')),
      skip: 1,
      expect: () => <ChatState>[],
      verify: (_) => expect(repository.typing, [true, false]),
    );

    blocTest<ChatBloc, ChatState>(
      'shows the peer typing and hides it when the indicator expires',
      build: () =>
          buildBloc(peerTypingTimeout: const Duration(milliseconds: 30)),
      act: (bloc) => repository.emitUpdate(
        PeerTypingChanged(
          conversationId: conversationId,
          userId: 'bob',
          isTyping: true,
        ),
      ),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<ChatState>().having((s) => s.isPeerTyping, 'isPeerTyping', true),
        isA<ChatState>().having((s) => s.isPeerTyping, 'isPeerTyping', false),
      ],
    );
  });

  group('loading', () {
    blocTest<ChatBloc, ChatState>(
      'shows cached messages first, then merges the latest page',
      setUp: () {
        repository
          ..cached = [message('m1', sender: 'bob')]
          ..historyPage = MessagePage(
            messages: [
              message('m2', at: t0.add(const Duration(minutes: 1))),
              message('m1', sender: 'bob'),
            ],
            hasMore: false,
          );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, ChatLoadStatus.ready);
        expect(bloc.state.messages.map((m) => m.id), ['m2', 'm1']);
        expect(bloc.state.messages.last.status, MessageStatus.read);
        expect(bloc.state.hasMore, isFalse);
        expect(repository.readReceipts, [
          ['m1'],
        ]);
      },
    );

    blocTest<ChatBloc, ChatState>(
      'loads older messages before the oldest one shown',
      setUp: () => repository.historyPage = MessagePage(
        messages: [message('m1', at: t0)],
        hasMore: false,
      ),
      build: buildBloc,
      seed: () => readyState([
        message('m3', at: t0.add(const Duration(minutes: 2))),
        message('m2', at: t0.add(const Duration(minutes: 1))),
      ]),
      act: (bloc) => bloc.add(const ChatOlderRequested()),
      expect: () => [
        isA<ChatState>().having((s) => s.isLoadingOlder, 'loading', true),
        isA<ChatState>()
            .having((s) => s.isLoadingOlder, 'loading', false)
            .having((s) => s.hasMore, 'hasMore', false)
            .having(
              (s) => s.messages.map((m) => m.id).toList(),
              'ids',
              ['m3', 'm2', 'm1'],
            ),
      ],
      verify: (_) => expect(
        repository.historyRequests,
        [t0.add(const Duration(minutes: 1))],
      ),
    );

    blocTest<ChatBloc, ChatState>(
      'does not page when there is nothing more to load',
      build: buildBloc,
      seed: () => readyState([message('m1')], hasMore: false),
      act: (bloc) => bloc.add(const ChatOlderRequested()),
      expect: () => <ChatState>[],
      verify: (_) => expect(repository.historyRequests, isEmpty),
    );
  });
}

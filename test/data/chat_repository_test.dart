import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/data/connection/backoff_policy.dart';
import 'package:realtime_chat/data/connection/connection_manager.dart';
import 'package:realtime_chat/data/local/chat_cache.dart';
import 'package:realtime_chat/data/local/outbox.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/data/repositories/chat_repository_impl.dart';
import 'package:realtime_chat/domain/entities/chat_update.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/conversation.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';

import '../helpers/test_chat_socket.dart';

const alice = ChatUser(id: 'alice', name: 'Alice');
const bob = ChatUser(id: 'bob', name: 'Bob', isOnline: true);
final conversationId = ConversationIds.direct('alice', 'bob');

Message outgoing(String clientId, String text) {
  return Message(
    id: clientId,
    clientId: clientId,
    conversationId: conversationId,
    senderId: 'alice',
    text: text,
    sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
    status: MessageStatus.sending,
  );
}

class _Harness {
  _Harness(this.store, {int failures = 0})
      : socket = TestChatSocket()..failuresRemaining = failures {
    connection = ConnectionManager(
      socket: socket,
      uri: Uri.parse('ws://test'),
      backoff: const BackoffPolicy(jitter: 0),
      heartbeatInterval: null,
    );
    repository = ChatRepositoryImpl(
      connection: connection,
      cache: ChatCache(store, userId: 'alice'),
      outbox: Outbox(store, userId: 'alice'),
      me: alice,
    );
  }

  final KeyValueStore store;
  final TestChatSocket socket;
  late final ConnectionManager connection;
  late final ChatRepositoryImpl repository;

  List<String> get pendingInOutbox =>
      [for (final m in (Outbox(store, userId: 'alice')..load()).pending) m.clientId];

  void dispose(FakeAsync fake) {
    repository.dispose();
    connection.dispose();
    fake.flushMicrotasks();
  }
}

void main() {
  late InMemoryKeyValueStore store;

  setUp(() => store = InMemoryKeyValueStore());

  test('sends hello first, then flushes the outbox in order on reconnect', () {
    fakeAsync((fake) {
      final h = _Harness(store, failures: 1)..repository.start();
      fake.flushMicrotasks();

      h.repository.send(outgoing('c1', 'one'));
      h.repository.send(outgoing('c2', 'two'));
      fake.flushMicrotasks();
      expect(h.socket.sent, isEmpty);
      expect(h.pendingInOutbox, ['c1', 'c2']);

      fake.elapse(const Duration(seconds: 1));

      expect(h.socket.sentTypes, ['hello', 'send', 'send']);
      expect(
        [for (final f in h.socket.sent.skip(1)) f['clientId']],
        ['c1', 'c2'],
      );
      h.dispose(fake);
    });
  });

  test('removes acknowledged messages from the outbox', () {
    fakeAsync((fake) {
      final h = _Harness(store)..repository.start();
      final updates = <ChatUpdate>[];
      h.repository.updates.listen(updates.add);
      fake.flushMicrotasks();

      h.repository.send(outgoing('c1', 'one'));
      h.repository.send(outgoing('c2', 'two'));
      fake.flushMicrotasks();
      expect(h.socket.sentTypes, ['hello', 'send', 'send']);

      final acked = outgoing('c1', 'one').copyWith(
        id: 'm1',
        status: MessageStatus.sent,
      );
      h.socket.push(AckFrame(clientId: 'c1', message: acked));
      fake.flushMicrotasks();

      expect(h.pendingInOutbox, ['c2']);
      expect(updates, contains(MessageAcknowledged(clientId: 'c1', message: acked)));
      h.dispose(fake);
    });
  });

  test('resends unacknowledged messages after a dropped connection', () {
    fakeAsync((fake) {
      final h = _Harness(store)..repository.start();
      fake.flushMicrotasks();
      h.repository.send(outgoing('c1', 'one'));
      fake.flushMicrotasks();

      h.socket.drop();
      fake.elapse(const Duration(seconds: 1));

      expect(h.socket.sentTypes, ['hello', 'send', 'hello', 'send']);
      expect(h.socket.sent.last['clientId'], 'c1');
      h.dispose(fake);
    });
  });

  test('keeps the outbox across restarts', () {
    fakeAsync((fake) {
      final first = _Harness(store, failures: 1000)..repository.start();
      fake.flushMicrotasks();
      first.repository.send(outgoing('c1', 'offline message'));
      fake.flushMicrotasks();
      first.dispose(fake);

      final second = _Harness(store)..repository.start();
      fake.flushMicrotasks();
      expect(second.socket.sentTypes, ['hello', 'send']);
      expect(second.socket.sent.last['text'], 'offline message');
      second.dispose(fake);
    });
  });

  test('a server rejection fails the message and drops it from the outbox', () {
    fakeAsync((fake) {
      final h = _Harness(store)..repository.start();
      final updates = <ChatUpdate>[];
      h.repository.updates.listen(updates.add);
      fake.flushMicrotasks();

      h.repository.send(outgoing('c1', 'nope'));
      fake.flushMicrotasks();
      h.socket.push(
        const ErrorFrame(code: 'rejected', message: 'Rejected', clientId: 'c1'),
      );
      fake.flushMicrotasks();

      expect(h.pendingInOutbox, isEmpty);
      expect(
        updates.whereType<MessageFailed>().single.clientId,
        'c1',
      );
      List<Message>? cached;
      h.repository.cachedMessages(conversationId).then((m) => cached = m);
      fake.flushMicrotasks();
      expect(cached?.single.status, MessageStatus.failed);
      h.dispose(fake);
    });
  });

  test('incoming messages bump unread, send a delivery receipt and reset on read', () {
    fakeAsync((fake) {
      final h = _Harness(store)..repository.start();
      final snapshots = <List<Conversation>>[];
      h.repository.watchConversations().listen(snapshots.add);
      fake.flushMicrotasks();

      h.socket.push(const WelcomeFrame(user: alice, users: [bob]));
      fake.flushMicrotasks();

      final incoming = Message(
        id: 'm9',
        clientId: 'b1',
        conversationId: conversationId,
        senderId: 'bob',
        text: 'hey',
        sentAt: DateTime.fromMillisecondsSinceEpoch(5000),
      );
      h.socket.push(IncomingMessageFrame(incoming));
      fake.flushMicrotasks();

      expect(snapshots.last.single.unreadCount, 1);
      expect(snapshots.last.single.lastMessage?.id, 'm9');
      final receipt = h.socket.sent.last;
      expect(receipt['type'], 'receipt');
      expect(receipt['status'], 'delivered');
      expect(receipt['messageIds'], ['m9']);

      h.repository.markRead(conversationId, ['m9']);
      fake.flushMicrotasks();
      expect(snapshots.last.single.unreadCount, 0);
      expect(h.socket.sent.last['status'], 'read');
      h.dispose(fake);
    });
  });
}

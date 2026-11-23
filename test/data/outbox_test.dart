import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/data/local/outbox.dart';
import 'package:realtime_chat/domain/entities/message.dart';

Message pending(String clientId) => Message(
      id: clientId,
      clientId: clientId,
      conversationId: 'dm:alice:bob',
      senderId: 'alice',
      text: 'text $clientId',
      sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
      status: MessageStatus.sending,
    );

void main() {
  late InMemoryKeyValueStore store;

  setUp(() => store = InMemoryKeyValueStore());

  test('keeps insertion order and survives a reload', () async {
    final outbox = Outbox(store, userId: 'alice');
    await outbox.add(pending('c1'));
    await outbox.add(pending('c2'));
    await outbox.add(pending('c3'));
    await outbox.remove('c2');

    final reloaded = Outbox(store, userId: 'alice')..load();
    expect(reloaded.pending.map((m) => m.clientId), ['c1', 'c3']);
    expect(reloaded.pending.first, pending('c1'));
  });

  test('re-adding a message replaces it instead of duplicating it', () async {
    final outbox = Outbox(store, userId: 'alice');
    await outbox.add(pending('c1'));
    await outbox.add(pending('c1').copyWith(text: 'edited'));

    expect(outbox.pending, hasLength(1));
    expect(outbox.find('c1')?.text, 'edited');
  });

  test('is scoped per user', () async {
    await Outbox(store, userId: 'alice').add(pending('c1'));
    final bobs = Outbox(store, userId: 'bob')..load();
    expect(bobs.isEmpty, isTrue);
  });

  test('ignores corrupt data', () {
    final corrupt = InMemoryKeyValueStore({'chat:alice:outbox': '{not json'});
    final outbox = Outbox(corrupt, userId: 'alice')..load();
    expect(outbox.isEmpty, isTrue);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:realtime_chat_server/chat_server.dart';
import 'package:test/test.dart';

void main() {
  late ChatServer server;

  setUp(() async {
    server = ChatServer(log: (_) {});
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() => server.close());

  Map<String, dynamic> sendFrame(String from, String to, String clientId, String text) => {
        'type': 'send',
        'clientId': clientId,
        'conversationId': directId(from, to),
        'to': to,
        'text': text,
        'sentAt': 0,
      };

  test('relays a message, acks the sender and forwards read receipts', () async {
    final alice = await _Client.connect(server.port, 'alice');
    final bob = await _Client.connect(server.port, 'bob');
    await alice.next('welcome');
    await bob.next('welcome');

    alice.send(sendFrame('alice', 'bob', 'c1', 'Hi Bob'));
    final ack = await alice.next('ack');
    final incoming = await bob.next('message');
    final id = (ack['message'] as Map<String, dynamic>)['id'];
    expect((incoming['message'] as Map<String, dynamic>)['id'], id);
    expect((incoming['message'] as Map<String, dynamic>)['text'], 'Hi Bob');

    bob.send({
      'type': 'receipt',
      'conversationId': directId('alice', 'bob'),
      'to': 'alice',
      'messageIds': [id],
      'status': 'read',
    });
    final receipt = await alice.next('receipt');
    expect(receipt['status'], 'read');
    expect(receipt['messageIds'], [id]);

    await alice.close();
    await bob.close();
  });

  test('returns the original message when a send is retried', () async {
    final alice = await _Client.connect(server.port, 'alice');
    await alice.next('welcome');

    alice.send(sendFrame('alice', 'bob', 'c1', 'once'));
    alice.send(sendFrame('alice', 'bob', 'c1', 'once'));
    final first = await alice.next('ack');
    final second = await alice.next('ack');
    expect(
      (first['message'] as Map<String, dynamic>)['id'],
      (second['message'] as Map<String, dynamic>)['id'],
    );
    await alice.close();
  });

  test('hands undelivered messages to a user when they connect', () async {
    final alice = await _Client.connect(server.port, 'alice');
    await alice.next('welcome');
    alice.send(sendFrame('alice', 'bob', 'c1', 'while you were away'));
    await alice.next('ack');

    final bob = await _Client.connect(server.port, 'bob');
    final welcome = await bob.next('welcome');
    final pending = welcome['pending'] as List<dynamic>;
    expect(pending, hasLength(1));
    expect((pending.single as Map<String, dynamic>)['text'], 'while you were away');
    final summary = (welcome['conversations'] as List<dynamic>).single as Map<String, dynamic>;
    expect(summary['unreadCount'], 1);

    await alice.close();
    await bob.close();
  });

  test('broadcasts presence and serves paged history', () async {
    final alice = await _Client.connect(server.port, 'alice');
    await alice.next('welcome');
    final bob = await _Client.connect(server.port, 'bob');
    await bob.next('welcome');
    final online = await alice.next('presence');
    expect((online['user'] as Map<String, dynamic>)['online'], isTrue);

    for (var i = 0; i < 5; i++) {
      alice.send(sendFrame('alice', 'bob', 'c$i', 'message $i'));
      await alice.next('ack');
    }
    bob.send({
      'type': 'history',
      'requestId': 'h1',
      'conversationId': directId('alice', 'bob'),
      'limit': 3,
    });
    final page = await bob.next('history');
    final texts = [
      for (final m in page['messages'] as List<dynamic>) (m as Map<String, dynamic>)['text'],
    ];
    expect(texts, ['message 4', 'message 3', 'message 2']);
    expect(page['hasMore'], isTrue);

    await bob.close();
    final offline = await alice.next('presence');
    expect((offline['user'] as Map<String, dynamic>)['online'], isFalse);
    await alice.close();
  });

  test('rejects frames before hello and invalid messages', () async {
    final socket = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
    final client = _Client(socket);
    client.send(sendFrame('alice', 'bob', 'c1', 'too early'));
    final error = await client.next('error');
    expect(error['code'], 'unauthenticated');
    expect(error['clientId'], 'c1');

    client.send({'type': 'hello', 'userId': 'alice', 'name': 'Alice'});
    await client.next('welcome');
    client.send(sendFrame('alice', 'bob', 'c2', '   '));
    final invalid = await client.next('error');
    expect(invalid['code'], 'invalid_message');
    await client.close();
  });
}

/// Buffers incoming frames so tests can wait for a type in any order.
class _Client {
  _Client(this._socket) {
    _socket.listen((data) {
      _frames.add(jsonDecode(data as String) as Map<String, dynamic>);
      _deliver();
    });
  }

  static Future<_Client> connect(int port, String userId) async {
    final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final client = _Client(socket);
    client.send({'type': 'hello', 'userId': userId, 'name': userId});
    return client;
  }

  final WebSocket _socket;
  final List<Map<String, dynamic>> _frames = [];
  final List<(String, Completer<Map<String, dynamic>>)> _waiters = [];

  void send(Map<String, dynamic> frame) => _socket.add(jsonEncode(frame));

  Future<Map<String, dynamic>> next(String type) {
    final index = _frames.indexWhere((f) => f['type'] == type);
    if (index != -1) return Future.value(_frames.removeAt(index));
    final completer = Completer<Map<String, dynamic>>();
    _waiters.add((type, completer));
    return completer.future.timeout(const Duration(seconds: 5));
  }

  void _deliver() {
    for (final waiter in List.of(_waiters)) {
      final index = _frames.indexWhere((f) => f['type'] == waiter.$1);
      if (index == -1) continue;
      _waiters.remove(waiter);
      waiter.$2.complete(_frames.removeAt(index));
    }
  }

  Future<void> close() async {
    await _socket.close();
  }
}

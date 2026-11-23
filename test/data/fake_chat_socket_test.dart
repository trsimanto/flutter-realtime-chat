import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/data/protocol/client_frame.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/data/socket/chat_socket.dart';
import 'package:realtime_chat/data/socket/fake_chat_socket.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';

void main() {
  late FakeChatSocket socket;
  late List<ServerFrame> frames;

  void connect(FakeAsync fake) {
    socket = FakeChatSocket(random: Random(1));
    frames = [];
    socket.events.listen((event) {
      if (event is SocketMessage) {
        frames.add(
          ServerFrame.fromJson(jsonDecode(event.data) as Map<String, dynamic>),
        );
      }
    });
    socket.connect(Uri.parse('demo://local'));
    fake.elapse(const Duration(seconds: 1));
    socket.send(
      jsonEncode(const HelloFrame(userId: 'tester', name: 'Tester').toJson()),
    );
    fake.elapse(const Duration(seconds: 1));
  }

  void sendText(String to, String clientId, String text) {
    socket.send(
      jsonEncode(
        SendMessageFrame(
          clientId: clientId,
          conversationId: ConversationIds.direct('tester', to),
          to: to,
          text: text,
          sentAt: DateTime(2026),
        ).toJson(),
      ),
    );
  }

  test('greets with contacts, unread counts and pending messages', () {
    fakeAsync((fake) {
      connect(fake);
      final welcome = frames.whereType<WelcomeFrame>().single;
      expect(
        welcome.users.map((u) => u.id),
        containsAll(<String>['bot-ava', 'bot-mia', 'bot-leo']),
      );
      expect(welcome.pending, isNotEmpty);
      final mia = welcome.conversations.firstWhere(
        (c) => c.conversationId == ConversationIds.direct('tester', 'bot-mia'),
      );
      expect(mia.unreadCount, 2);
      socket.dispose();
    });
  });

  test('acknowledges, delivers, reads and replies to a message', () {
    fakeAsync((fake) {
      connect(fake);
      sendText('bot-ava', 'c1', 'Hi Ava');
      fake.elapse(const Duration(seconds: 6));

      expect(frames.whereType<AckFrame>().single.clientId, 'c1');
      expect(
        frames.whereType<PeerReceiptFrame>().map((r) => r.status),
        [MessageStatus.delivered, MessageStatus.read],
      );
      expect(
        frames.whereType<PeerTypingFrame>().map((t) => t.isTyping),
        [true, false],
      );
      expect(
        frames.whereType<IncomingMessageFrame>().single.message.senderId,
        'bot-ava',
      );
      socket.dispose();
    });
  });

  test('deduplicates a resent message by client id', () {
    fakeAsync((fake) {
      connect(fake);
      sendText('bot-mia', 'c1', 'Hello');
      sendText('bot-mia', 'c1', 'Hello');
      fake.elapse(const Duration(milliseconds: 300));

      final acks = frames.whereType<AckFrame>().toList();
      expect(acks, hasLength(2));
      expect(acks.first.message.id, acks.last.message.id);
      socket.dispose();
    });
  });

  test('rejects "/fail" so the failed state can be demoed', () {
    fakeAsync((fake) {
      connect(fake);
      sendText('bot-ava', 'c9', '/fail');
      fake.elapse(const Duration(milliseconds: 300));

      final error = frames.whereType<ErrorFrame>().single;
      expect(error.clientId, 'c9');
      socket.dispose();
    });
  });

  test('refuses to connect while the simulated network is down', () {
    fakeAsync((fake) {
      connect(fake);
      final closed = <SocketClosed>[];
      socket.events.listen((e) {
        if (e is SocketClosed) closed.add(e);
      });

      socket.setNetworkAvailable(available: false);
      fake.flushMicrotasks();
      expect(closed, hasLength(1));

      Object? error;
      socket.connect(Uri.parse('demo://local')).catchError((Object e) {
        error = e;
      });
      fake.elapse(const Duration(seconds: 1));
      expect(error, isA<SimulatedNetworkException>());
      socket.dispose();
    });
  });
}

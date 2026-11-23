import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/data/protocol/client_frame.dart';
import 'package:realtime_chat/data/protocol/json_mappers.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/message.dart';

final sentAt = DateTime.fromMillisecondsSinceEpoch(1767268800000);

Message sample() => Message(
      id: 'm1',
      clientId: 'c1',
      conversationId: 'dm:alice:bob',
      senderId: 'alice',
      text: 'Hello "Bob" \u{1F44B}',
      sentAt: sentAt,
      status: MessageStatus.delivered,
    );

/// Encodes to a JSON string and back, exactly like the socket does.
Map<String, dynamic> wire(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  group('JsonMappers', () {
    test('round-trips a message', () {
      final json = wire(JsonMappers.messageToJson(sample()));
      expect(json['sentAt'], sentAt.millisecondsSinceEpoch);
      expect(json['status'], 'delivered');
      expect(JsonMappers.message(json), sample());
    });

    test('tolerates missing optional fields', () {
      final parsed = JsonMappers.message({
        'id': 'm1',
        'conversationId': 'dm:a:b',
        'senderId': 'a',
        'text': 'hi',
        'sentAt': 0,
      });
      expect(parsed.clientId, isEmpty);
      expect(parsed.status, MessageStatus.sent);
    });

    test('round-trips a user with presence', () {
      final user = ChatUser(id: 'bob', name: 'Bob', lastSeen: sentAt);
      expect(JsonMappers.user(wire(JsonMappers.userToJson(user))), user);
    });
  });

  group('ClientFrame', () {
    final frames = <ClientFrame>[
      const HelloFrame(userId: 'alice', name: 'Alice'),
      SendMessageFrame.fromMessage(sample(), to: 'bob'),
      const TypingFrame(conversationId: 'dm:alice:bob', to: 'bob', isTyping: true),
      const ReceiptFrame(
        conversationId: 'dm:alice:bob',
        to: 'bob',
        messageIds: ['m1', 'm2'],
        status: MessageStatus.read,
      ),
      HistoryRequestFrame(
        requestId: 'h1',
        conversationId: 'dm:alice:bob',
        before: sentAt,
        limit: 20,
      ),
      const HistoryRequestFrame(requestId: 'h2', conversationId: 'dm:alice:bob'),
      const PingFrame(),
    ];

    for (final frame in frames) {
      test('round-trips ${frame.runtimeType}', () {
        expect(ClientFrame.fromJson(wire(frame.toJson())), frame);
      });
    }

    test('uses the documented wire format for send', () {
      final json = SendMessageFrame.fromMessage(sample(), to: 'bob').toJson();
      expect(json, {
        'type': 'send',
        'clientId': 'c1',
        'conversationId': 'dm:alice:bob',
        'to': 'bob',
        'text': sample().text,
        'sentAt': sentAt.millisecondsSinceEpoch,
      });
    });

    test('returns null for unknown frame types', () {
      expect(ClientFrame.fromJson({'type': 'teleport'}), isNull);
    });
  });

  group('ServerFrame', () {
    final frames = <ServerFrame>[
      WelcomeFrame(
        user: const ChatUser(id: 'alice', name: 'Alice', isOnline: true),
        users: [ChatUser(id: 'bob', name: 'Bob', lastSeen: sentAt)],
        conversations: [
          ConversationSummary(
            conversationId: 'dm:alice:bob',
            lastMessage: sample(),
            unreadCount: 3,
          ),
          const ConversationSummary(conversationId: 'dm:alice:carol'),
        ],
        pending: [sample()],
      ),
      AckFrame(clientId: 'c1', message: sample()),
      IncomingMessageFrame(sample()),
      const PeerTypingFrame(
        conversationId: 'dm:alice:bob',
        userId: 'bob',
        isTyping: false,
      ),
      const PeerReceiptFrame(
        conversationId: 'dm:alice:bob',
        userId: 'bob',
        messageIds: ['m1'],
        status: MessageStatus.delivered,
      ),
      const PresenceFrame(ChatUser(id: 'bob', name: 'Bob', isOnline: true)),
      HistoryFrame(
        requestId: 'h1',
        conversationId: 'dm:alice:bob',
        messages: [sample()],
        hasMore: true,
      ),
      const ErrorFrame(code: 'rejected', message: 'Nope', clientId: 'c1'),
      const ErrorFrame(code: 'bad_frame', message: 'Bad'),
      const PongFrame(),
    ];

    for (final frame in frames) {
      test('round-trips ${frame.runtimeType}', () {
        expect(ServerFrame.fromJson(wire(frame.toJson())), frame);
      });
    }

    test('maps unknown types to UnknownServerFrame', () {
      expect(
        ServerFrame.fromJson({'type': 'future_feature'}),
        const UnknownServerFrame('future_feature'),
      );
    });
  });
}

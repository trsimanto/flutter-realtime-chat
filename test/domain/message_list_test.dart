import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/domain/entities/message.dart';
import 'package:realtime_chat/domain/entities/session.dart';
import 'package:realtime_chat/domain/utils/conversation_ids.dart';
import 'package:realtime_chat/domain/utils/message_list.dart';

Message msg(
  String id, {
  String? clientId,
  int minute = 0,
  MessageStatus status = MessageStatus.sent,
}) {
  return Message(
    id: id,
    clientId: clientId ?? id,
    conversationId: 'dm:a:b',
    senderId: 'a',
    text: id,
    sentAt: DateTime(2026, 1, 1, 12, minute),
    status: status,
  );
}

void main() {
  group('MessageStatus.advanceTo', () {
    test('only moves forward', () {
      expect(MessageStatus.read.advanceTo(MessageStatus.delivered),
          MessageStatus.read);
      expect(MessageStatus.sent.advanceTo(MessageStatus.delivered),
          MessageStatus.delivered);
    });

    test('lets a failed message be retried and a pending one fail', () {
      expect(MessageStatus.failed.advanceTo(MessageStatus.sending),
          MessageStatus.sending);
      expect(MessageStatus.sending.advanceTo(MessageStatus.failed),
          MessageStatus.failed);
    });
  });

  group('MessageList', () {
    test('merges by client id and keeps newest first', () {
      final optimistic = msg('c1', minute: 5, status: MessageStatus.sending);
      final acked = msg('m1', clientId: 'c1', minute: 5);
      final result = MessageList.merge(
        [optimistic, msg('m0', minute: 1)],
        [acked, msg('m2', minute: 9)],
      );
      expect(result.map((m) => m.id), ['m2', 'm1', 'm0']);
      expect(result[1].status, MessageStatus.sent);
    });

    test('does not regress status when an older copy arrives', () {
      final result = MessageList.upsert(
        [msg('m1', status: MessageStatus.read)],
        msg('m1', status: MessageStatus.delivered),
      );
      expect(result.single.status, MessageStatus.read);
    });

    test('updates status only for the given ids', () {
      final result = MessageList.updateStatus(
        [msg('m1'), msg('m2')],
        {'m2'},
        MessageStatus.read,
      );
      expect(result.map((m) => m.status),
          [MessageStatus.sent, MessageStatus.read]);
    });
  });

  group('ConversationIds', () {
    test('is symmetric and resolves the peer', () {
      final id = ConversationIds.direct('zoe', 'adam');
      expect(id, ConversationIds.direct('adam', 'zoe'));
      expect(ConversationIds.peerOf(id, 'zoe'), 'adam');
      expect(ConversationIds.peerOf(id, 'carol'), isNull);
    });
  });

  group('Session.slugFor', () {
    test('creates url safe ids', () {
      expect(Session.slugFor('  Towhid R. '), 'towhid-r');
      expect(Session.slugFor('Ava'), 'ava');
      expect(Session.slugFor(''), isEmpty);
      expect(Session.slugFor('তা'), startsWith('user-'));
    });
  });
}

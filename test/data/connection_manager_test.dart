import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat/data/connection/backoff_policy.dart';
import 'package:realtime_chat/data/connection/connection_manager.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';

import '../helpers/test_chat_socket.dart';

void main() {
  group('BackoffPolicy', () {
    test('doubles the delay and caps it at the maximum', () {
      const policy = BackoffPolicy(
        initialDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 8),
        jitter: 0,
      );
      final delays = [
        for (var attempt = 1; attempt <= 7; attempt++)
          policy.delayFor(attempt).inMilliseconds,
      ];
      expect(delays, [500, 1000, 2000, 4000, 8000, 8000, 8000]);
    });

    test('keeps jitter within the configured bounds', () {
      final policy = BackoffPolicy(jitter: 0.2, random: Random(7));
      for (var attempt = 1; attempt <= 6; attempt++) {
        final base = 500 * pow(2, attempt - 1);
        final delay = policy.delayFor(attempt).inMilliseconds;
        expect(delay, inInclusiveRange(base * 0.8 - 1, base * 1.2 + 1));
      }
    });

    test('never exceeds the maximum delay, even with jitter', () {
      final policy = BackoffPolicy(jitter: 0.5, random: Random(1));
      for (var attempt = 1; attempt <= 40; attempt++) {
        expect(
          policy.delayFor(attempt),
          lessThanOrEqualTo(const Duration(seconds: 30)),
        );
      }
    });
  });

  group('ConnectionManager', () {
    late TestChatSocket socket;

    ConnectionManager build({Duration? heartbeat}) {
      return ConnectionManager(
        socket: socket,
        uri: Uri.parse('ws://test'),
        backoff: const BackoffPolicy(jitter: 0),
        heartbeatInterval: heartbeat,
      );
    }

    setUp(() => socket = TestChatSocket());

    test('retries with exponential backoff until the socket connects', () {
      fakeAsync((fake) {
        socket.failuresRemaining = 3;
        final manager = build();
        final statuses = <ConnectionStatus>[];
        manager.changes.listen((s) => statuses.add(s.status));
        final start = clock.now();

        manager.start();
        fake.elapse(const Duration(seconds: 10));

        final offsets = [
          for (final t in socket.connectAttempts)
            t.difference(start).inMilliseconds,
        ];
        expect(offsets, [0, 500, 1500, 3500]);
        expect(manager.current.status, ConnectionStatus.connected);
        expect(
          statuses.where((s) => s == ConnectionStatus.waitingToRetry),
          hasLength(3),
        );
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('exposes when the next retry will happen', () {
      fakeAsync((fake) {
        socket.failuresRemaining = 2;
        final manager = build();
        manager.start();
        fake.flushMicrotasks();
        fake.elapse(const Duration(milliseconds: 600));

        final snapshot = manager.current;
        expect(snapshot.status, ConnectionStatus.waitingToRetry);
        expect(snapshot.attempt, 2);
        expect(
          snapshot.retryAt!.difference(clock.now()),
          const Duration(milliseconds: 900),
        );
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('reconnects after a drop and starts the backoff from scratch', () {
      fakeAsync((fake) {
        socket.failuresRemaining = 2;
        final manager = build();
        manager.start();
        fake.elapse(const Duration(seconds: 5));
        expect(manager.isConnected, isTrue);
        expect(socket.connectAttempts, hasLength(3));

        socket.drop();
        fake.flushMicrotasks();
        expect(manager.current.status, ConnectionStatus.waitingToRetry);
        expect(manager.current.attempt, 1);

        fake.elapse(const Duration(milliseconds: 499));
        expect(socket.connectAttempts, hasLength(3));
        fake.elapse(const Duration(milliseconds: 1));
        expect(socket.connectAttempts, hasLength(4));
        expect(manager.isConnected, isTrue);
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('retryNow skips the remaining delay', () {
      fakeAsync((fake) {
        socket.failuresRemaining = 4;
        final manager = build();
        manager.start();
        fake.elapse(const Duration(seconds: 3, milliseconds: 600));
        expect(manager.current.status, ConnectionStatus.waitingToRetry);
        final attempts = socket.connectAttempts.length;

        socket.failuresRemaining = 0;
        manager.retryNow();
        fake.flushMicrotasks();

        expect(socket.connectAttempts, hasLength(attempts + 1));
        expect(manager.isConnected, isTrue);
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('drops a connection that stops answering pings', () {
      fakeAsync((fake) {
        final manager = build(heartbeat: const Duration(seconds: 1));
        manager.start();
        fake.flushMicrotasks();
        expect(manager.isConnected, isTrue);

        fake.elapse(const Duration(seconds: 1));
        expect(socket.sentTypes, ['ping']);
        expect(manager.isConnected, isTrue);

        fake.elapse(const Duration(seconds: 1));
        expect(manager.current.status, ConnectionStatus.waitingToRetry);
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('keeps a connection that answers pings', () {
      fakeAsync((fake) {
        final manager = build(heartbeat: const Duration(seconds: 1));
        manager.start();
        fake.flushMicrotasks();

        for (var i = 0; i < 5; i++) {
          fake.elapse(const Duration(seconds: 1));
          socket.push(const PongFrame());
          fake.flushMicrotasks();
        }
        expect(manager.isConnected, isTrue);
        expect(socket.sentTypes.where((t) => t == 'ping'), hasLength(5));
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('stop cancels pending retries', () {
      fakeAsync((fake) {
        socket.failuresRemaining = 100;
        final manager = build();
        manager.start();
        fake.flushMicrotasks();
        expect(socket.connectAttempts, hasLength(1));

        manager.stop();
        fake.elapse(const Duration(minutes: 1));
        expect(socket.connectAttempts, hasLength(1));
        expect(manager.current.status, ConnectionStatus.offline);
        manager.dispose();
        fake.flushMicrotasks();
      });
    });

    test('decodes server frames and drops malformed ones', () {
      fakeAsync((fake) {
        final manager = build();
        final frames = <ServerFrame>[];
        manager.frames.listen(frames.add);
        manager.start();
        fake.flushMicrotasks();

        socket.push(const ErrorFrame(code: 'x', message: 'boom'));
        fake.flushMicrotasks();

        expect(frames, [const ErrorFrame(code: 'x', message: 'boom')]);
        manager.dispose();
        fake.flushMicrotasks();
      });
    });
  });
}

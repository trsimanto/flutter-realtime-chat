import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/data/socket/chat_socket.dart';

/// Scriptable socket: fail the next N connects, inspect sent frames and push
/// server frames by hand.
class TestChatSocket implements ChatSocket {
  final _events = StreamController<SocketEvent>.broadcast();
  final List<DateTime> connectAttempts = [];
  final List<Map<String, dynamic>> sent = [];
  int failuresRemaining = 0;
  bool isOpen = false;

  List<String> get sentTypes => [for (final f in sent) f['type'] as String];

  @override
  Stream<SocketEvent> get events => _events.stream;

  @override
  Future<void> connect(Uri uri) async {
    connectAttempts.add(clock.now());
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('connection refused');
    }
    isOpen = true;
  }

  @override
  void send(String data) {
    if (!isOpen) throw StateError('closed');
    sent.add(jsonDecode(data) as Map<String, dynamic>);
  }

  void push(ServerFrame frame) {
    _events.add(SocketMessage(jsonEncode(frame.toJson())));
  }

  void drop() {
    isOpen = false;
    _events.add(const SocketClosed('dropped'));
  }

  @override
  Future<void> disconnect() async {
    isOpen = false;
  }

  @override
  Future<void> dispose() async {
    isOpen = false;
    await _events.close();
  }
}

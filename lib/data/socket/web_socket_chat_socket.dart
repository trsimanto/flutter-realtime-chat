import 'dart:async';

import 'package:realtime_chat/data/socket/chat_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketChatSocket implements ChatSocket {
  WebSocketChatSocket({this.connectTimeout = const Duration(seconds: 10)});

  final Duration connectTimeout;
  final _events = StreamController<SocketEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  @override
  Stream<SocketEvent> get events => _events.stream;

  @override
  Future<void> connect(Uri uri) async {
    await disconnect();
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(connectTimeout);
    } catch (_) {
      unawaited(channel.sink.close());
      rethrow;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      (data) {
        if (data is String) _events.add(SocketMessage(data));
      },
      onError: (Object error) => _onClosed(channel, error),
      onDone: () => _onClosed(channel, null),
      cancelOnError: true,
    );
  }

  void _onClosed(WebSocketChannel channel, Object? error) {
    if (!identical(channel, _channel)) return;
    _channel = null;
    _subscription = null;
    if (!_events.isClosed) _events.add(SocketClosed(error));
  }

  @override
  void send(String data) {
    final channel = _channel;
    if (channel == null) throw StateError('Socket is not connected');
    channel.sink.add(data);
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    await subscription?.cancel();
    if (channel != null) unawaited(channel.sink.close());
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}

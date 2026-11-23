sealed class SocketEvent {
  const SocketEvent();
}

final class SocketMessage extends SocketEvent {
  const SocketMessage(this.data);

  final String data;
}

/// The remote side went away. Not emitted for a local [ChatSocket.disconnect].
final class SocketClosed extends SocketEvent {
  const SocketClosed([this.error]);

  final Object? error;
}

/// Transport abstraction so the connection logic can run against a real
/// WebSocket, the in-app demo server, or a test double.
abstract interface class ChatSocket {
  /// Long-lived stream that spans reconnects.
  Stream<SocketEvent> get events;

  /// Completes once the connection is open, throws if it can't be opened.
  Future<void> connect(Uri uri);

  /// Throws if the socket is not open.
  void send(String data);

  Future<void> disconnect();

  Future<void> dispose();
}

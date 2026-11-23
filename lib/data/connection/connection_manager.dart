import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:realtime_chat/data/connection/backoff_policy.dart';
import 'package:realtime_chat/data/protocol/client_frame.dart';
import 'package:realtime_chat/data/protocol/server_frame.dart';
import 'package:realtime_chat/data/socket/chat_socket.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';
import 'package:realtime_chat/domain/repositories/connection_monitor.dart';

/// Keeps a [ChatSocket] connected: retries with exponential backoff, detects
/// silent connections with a ping/pong heartbeat, and decodes frames.
class ConnectionManager implements ConnectionMonitor {
  ConnectionManager({
    required ChatSocket socket,
    required Uri uri,
    BackoffPolicy backoff = const BackoffPolicy(),
    this.heartbeatInterval = const Duration(seconds: 20),
  })  : _socket = socket,
        _uri = uri,
        _backoff = backoff;

  /// Set to null to disable the heartbeat.
  final Duration? heartbeatInterval;

  final ChatSocket _socket;
  final Uri _uri;
  final BackoffPolicy _backoff;
  final _frames = StreamController<ServerFrame>.broadcast();
  final _changes = StreamController<ConnectionSnapshot>.broadcast();

  StreamSubscription<SocketEvent>? _socketSubscription;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  ConnectionSnapshot _current = const ConnectionSnapshot.offline();
  bool _running = false;
  bool _connecting = false;
  bool _awaitingPong = false;
  int _failures = 0;

  Stream<ServerFrame> get frames => _frames.stream;

  @override
  Stream<ConnectionSnapshot> get changes => _changes.stream;

  @override
  ConnectionSnapshot get current => _current;

  bool get isConnected => _current.isConnected;

  void start() {
    if (_running) return;
    _running = true;
    _socketSubscription ??= _socket.events.listen(_onSocketEvent);
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopHeartbeat();
    _failures = 0;
    await _socket.disconnect();
    _update(const ConnectionSnapshot.offline());
  }

  Future<void> dispose() async {
    await stop();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _frames.close();
    await _changes.close();
  }

  /// Returns false when the frame could not be handed to the socket.
  bool send(ClientFrame frame) {
    if (!isConnected) return false;
    try {
      _socket.send(jsonEncode(frame.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void retryNow() {
    if (!_running || _current.status != ConnectionStatus.waitingToRetry) {
      return;
    }
    unawaited(_connect());
  }

  @override
  void simulateDrop() => _dropConnection();

  Future<void> _connect() async {
    if (!_running || _connecting || isConnected) return;
    _connecting = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _update(
      ConnectionSnapshot(
        status: ConnectionStatus.connecting,
        attempt: _failures + 1,
      ),
    );

    try {
      await _socket.connect(_uri);
    } catch (_) {
      _connecting = false;
      if (_running) _scheduleRetry();
      return;
    }

    _connecting = false;
    if (!_running) {
      await _socket.disconnect();
      return;
    }
    _failures = 0;
    _update(const ConnectionSnapshot.connected());
    _startHeartbeat();
  }

  void _scheduleRetry() {
    _failures++;
    final delay = _backoff.delayFor(_failures);
    _update(
      ConnectionSnapshot(
        status: ConnectionStatus.waitingToRetry,
        attempt: _failures,
        retryAt: clock.now().add(delay),
      ),
    );
    _retryTimer = Timer(delay, () => unawaited(_connect()));
  }

  void _onSocketEvent(SocketEvent event) {
    switch (event) {
      case SocketMessage(:final data):
        _awaitingPong = false;
        final frame = _decode(data);
        if (frame != null && frame is! PongFrame) _frames.add(frame);
      case SocketClosed():
        _onConnectionLost();
    }
  }

  ServerFrame? _decode(String data) {
    try {
      final json = jsonDecode(data);
      return json is Map<String, dynamic> ? ServerFrame.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  void _dropConnection() {
    if (!isConnected) return;
    unawaited(_socket.disconnect());
    _onConnectionLost();
  }

  void _onConnectionLost() {
    if (!isConnected) return;
    _stopHeartbeat();
    if (_running) {
      _scheduleRetry();
    } else {
      _update(const ConnectionSnapshot.offline());
    }
  }

  void _startHeartbeat() {
    final interval = heartbeatInterval;
    if (interval == null) return;
    _heartbeatTimer?.cancel();
    _awaitingPong = false;
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (_awaitingPong) {
        _dropConnection();
        return;
      }
      _awaitingPong = send(const PingFrame());
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _awaitingPong = false;
  }

  void _update(ConnectionSnapshot snapshot) {
    _current = snapshot;
    if (!_changes.isClosed) _changes.add(snapshot);
  }
}

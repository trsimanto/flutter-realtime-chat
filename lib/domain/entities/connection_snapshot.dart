import 'package:equatable/equatable.dart';

enum ConnectionStatus { offline, connecting, connected, waitingToRetry }

class ConnectionSnapshot extends Equatable {
  const ConnectionSnapshot({
    required this.status,
    this.attempt = 0,
    this.retryAt,
  });

  const ConnectionSnapshot.offline() : this(status: ConnectionStatus.offline);

  const ConnectionSnapshot.connected()
      : this(status: ConnectionStatus.connected);

  final ConnectionStatus status;

  /// Number of consecutive failed attempts (or the attempt in progress).
  final int attempt;

  /// When the next attempt is scheduled, if waiting.
  final DateTime? retryAt;

  bool get isConnected => status == ConnectionStatus.connected;

  @override
  List<Object?> get props => [status, attempt, retryAt];
}

import 'package:realtime_chat/domain/entities/connection_snapshot.dart';

abstract interface class ConnectionMonitor {
  ConnectionSnapshot get current;

  Stream<ConnectionSnapshot> get changes;

  /// Skips the remaining backoff delay and reconnects immediately.
  void retryNow();

  /// Drops the live connection as if the network went away.
  void simulateDrop();
}

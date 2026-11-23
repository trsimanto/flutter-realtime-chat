import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';
import 'package:realtime_chat/domain/repositories/connection_monitor.dart';

class ConnectionCubit extends Cubit<ConnectionSnapshot> {
  ConnectionCubit(this._monitor) : super(_monitor.current) {
    _subscription = _monitor.changes.listen(emit);
  }

  final ConnectionMonitor _monitor;
  late final StreamSubscription<ConnectionSnapshot> _subscription;

  void retryNow() => _monitor.retryNow();

  void simulateDrop() => _monitor.simulateDrop();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}

import 'dart:math';

import 'package:clock/clock.dart';

typedef IdGenerator = String Function();

abstract final class IdGenerators {
  static final Random _random = Random();

  /// Time-prefixed id that is unique enough for client-side deduplication.
  static String clientId() {
    final time = clock.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'c_$time$salt';
  }
}

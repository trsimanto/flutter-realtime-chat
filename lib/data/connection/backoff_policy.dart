import 'dart:math';

/// Exponential backoff with optional jitter, capped at [maxDelay].
class BackoffPolicy {
  const BackoffPolicy({
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitter = 0.2,
    this.random,
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  /// Fraction of the delay to randomise by, in both directions. Spreads out
  /// reconnect storms when a server restarts.
  final double jitter;
  final Random? random;

  static final Random _sharedRandom = Random();

  /// Delay before retry number [attempt], starting at 1.
  Duration delayFor(int attempt) {
    if (attempt < 1) return Duration.zero;
    final maxMs = maxDelay.inMilliseconds.toDouble();
    final raw = initialDelay.inMilliseconds * pow(multiplier, attempt - 1);
    final base = min(raw.toDouble(), maxMs);
    final spread = jitter <= 0
        ? 0.0
        : base * jitter * ((random ?? _sharedRandom).nextDouble() * 2 - 1);
    final ms = min(max(base + spread, 0.0), maxMs);
    return Duration(milliseconds: ms.round());
  }
}

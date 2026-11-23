import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/domain/entities/connection_snapshot.dart';
import 'package:realtime_chat/presentation/connection/connection_cubit.dart';

/// Thin status strip shown under the app bar whenever we are not connected.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<ConnectionCubit, ConnectionSnapshot>(
      builder: (context, snapshot) {
        final Widget content = switch (snapshot.status) {
          ConnectionStatus.connected => const SizedBox(width: double.infinity),
          ConnectionStatus.connecting => _BannerBar(
              key: const ValueKey('connecting'),
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
              leading: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              label: Text(
                snapshot.attempt > 1
                    ? 'Reconnecting (attempt ${snapshot.attempt})'
                    : 'Connecting',
              ),
            ),
          ConnectionStatus.waitingToRetry => _BannerBar(
              key: const ValueKey('waiting'),
              background: scheme.errorContainer,
              foreground: scheme.onErrorContainer,
              leading: const Icon(Icons.cloud_off_rounded),
              label: _RetryCountdown(retryAt: snapshot.retryAt),
              action: TextButton(
                onPressed: context.read<ConnectionCubit>().retryNow,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                ),
                child: const Text('Retry now'),
              ),
            ),
          ConnectionStatus.offline => _BannerBar(
              key: const ValueKey('offline'),
              background: scheme.surfaceContainerHighest,
              foreground: scheme.onSurfaceVariant,
              leading: const Icon(Icons.cloud_off_rounded),
              label: const Text('Offline'),
            ),
        };
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: content,
        );
      },
    );
  }
}

class _BannerBar extends StatelessWidget {
  const _BannerBar({
    super.key,
    required this.background,
    required this.foreground,
    required this.leading,
    required this.label,
    this.action,
  });

  final Color background;
  final Color foreground;
  final Widget leading;
  final Widget label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(color: foreground, size: 18),
              child: leading,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: label,
              ),
            ),
            if (action != null) action else const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

class _RetryCountdown extends StatefulWidget {
  const _RetryCountdown({required this.retryAt});

  final DateTime? retryAt;

  @override
  State<_RetryCountdown> createState() => _RetryCountdownState();
}

class _RetryCountdownState extends State<_RetryCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final retryAt = widget.retryAt;
    final millis = retryAt == null
        ? 0
        : retryAt.difference(clock.now()).inMilliseconds;
    final seconds = (millis / 1000).ceil();
    return Text(
      seconds > 0 ? 'Offline. Retrying in ${seconds}s' : 'Offline. Retrying',
    );
  }
}

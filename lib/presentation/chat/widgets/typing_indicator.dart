import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.name});

  final String name;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            _Dot(animation: _controller, index: i, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${widget.name} is typing...',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.animation,
    required this.index,
    required this.color,
  });

  final Animation<double> animation;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = (animation.value - index * 0.2) % 1.0;
        final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
        return Opacity(opacity: 0.3 + 0.7 * wave, child: child);
      },
      child: Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

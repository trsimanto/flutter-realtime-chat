import 'package:flutter/material.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.showPresence = true,
  });

  final ChatUser user;
  final double radius;
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hash = user.id.codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final background = HSLColor.fromAHSL(
      1,
      (hash % 360).toDouble(),
      0.45,
      isDark ? 0.35 : 0.8,
    ).toColor();
    final dot = radius * 0.5;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: background,
          child: Text(
            _initials(user.name),
            style: TextStyle(
              fontSize: radius * 0.7,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        if (showPresence && user.isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              key: const ValueKey('presence-dot'),
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: const Color(0xFF2EB872),
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
    return letters.join();
  }
}

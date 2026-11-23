import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color _seed = Color(0xFF3D5AFE);

  /// Tick colour for read messages, readable on both bubble colours.
  static const Color readReceipt = Color(0xFF1E88E5);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 1,
      ),
    );
  }
}

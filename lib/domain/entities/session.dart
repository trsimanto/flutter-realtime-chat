import 'package:equatable/equatable.dart';

enum ChatMode { demo, server }

class Session extends Equatable {
  const Session({
    required this.userId,
    required this.displayName,
    required this.mode,
    this.serverUrl = '',
  });

  final String userId;
  final String displayName;
  final ChatMode mode;
  final String serverUrl;

  Uri get serverUri =>
      mode == ChatMode.demo ? Uri.parse('demo://local') : Uri.parse(serverUrl);

  /// Turns a display name into a stable, URL-safe user id.
  static String slugFor(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) {
      if (name.trim().isEmpty) return '';
      final hash = name.codeUnits.fold<int>(
        0,
        (value, unit) => (value * 31 + unit) & 0x7fffffff,
      );
      return 'user-${hash.toRadixString(36)}';
    }
    return slug.length > 24 ? slug.substring(0, 24) : slug;
  }

  @override
  List<Object?> get props => [userId, displayName, mode, serverUrl];
}

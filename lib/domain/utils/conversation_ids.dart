abstract final class ConversationIds {
  /// Direct conversations are keyed by both user ids in sorted order, so
  /// both sides derive the same id without a round trip.
  static String direct(String a, String b) {
    final ids = [a, b]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }

  static String? peerOf(String conversationId, String me) {
    final parts = conversationId.split(':');
    if (parts.length != 3 || parts[0] != 'dm') return null;
    if (parts[1] == me) return parts[2];
    if (parts[2] == me) return parts[1];
    return null;
  }
}

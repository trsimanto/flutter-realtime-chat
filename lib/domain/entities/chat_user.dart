import 'package:equatable/equatable.dart';

class ChatUser extends Equatable {
  const ChatUser({
    required this.id,
    required this.name,
    this.isOnline = false,
    this.lastSeen,
  });

  final String id;
  final String name;
  final bool isOnline;
  final DateTime? lastSeen;

  ChatUser copyWith({String? name, bool? isOnline, DateTime? lastSeen}) {
    return ChatUser(
      id: id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [id, name, isOnline, lastSeen];
}

import 'package:get_it/get_it.dart';
import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/data/connection/connection_manager.dart';
import 'package:realtime_chat/data/local/chat_cache.dart';
import 'package:realtime_chat/data/local/outbox.dart';
import 'package:realtime_chat/data/local/session_store.dart';
import 'package:realtime_chat/data/local/shared_preferences_store.dart';
import 'package:realtime_chat/data/repositories/chat_repository_impl.dart';
import 'package:realtime_chat/data/socket/chat_socket.dart';
import 'package:realtime_chat/data/socket/fake_chat_socket.dart';
import 'package:realtime_chat/data/socket/web_socket_chat_socket.dart';
import 'package:realtime_chat/domain/entities/chat_user.dart';
import 'package:realtime_chat/domain/entities/session.dart';
import 'package:realtime_chat/domain/repositories/chat_repository.dart';
import 'package:realtime_chat/domain/repositories/connection_monitor.dart';
import 'package:realtime_chat/domain/repositories/network_simulator.dart';
import 'package:realtime_chat/domain/usecases/send_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt getIt = GetIt.instance;

const String _sessionScope = 'session';

/// App-wide singletons that outlive a signed-in session.
Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  getIt
    ..registerSingleton<KeyValueStore>(SharedPreferencesStore(prefs))
    ..registerLazySingleton<SessionStore>(
      () => SessionStore(getIt<KeyValueStore>()),
    );
}

/// Everything tied to the signed-in user lives in its own scope, so signing
/// out tears down the socket, connection and repository in one go.
Future<void> openSession(Session session) async {
  await closeSession();
  final me = ChatUser(
    id: session.userId,
    name: session.displayName,
    isOnline: true,
  );

  getIt.pushNewScope(
    scopeName: _sessionScope,
    init: (scope) {
      final ChatSocket socket = session.mode == ChatMode.demo
          ? FakeChatSocket()
          : WebSocketChatSocket();
      scope.registerSingleton<ChatSocket>(
        socket,
        dispose: (s) => s.dispose(),
      );
      if (socket is FakeChatSocket) {
        scope.registerSingleton<NetworkSimulator>(socket);
      }
      scope
        ..registerLazySingleton<ConnectionManager>(
          () => ConnectionManager(
            socket: scope<ChatSocket>(),
            uri: session.serverUri,
          ),
          dispose: (manager) => manager.dispose(),
        )
        ..registerLazySingleton<ConnectionMonitor>(
          () => scope<ConnectionManager>(),
        )
        ..registerLazySingleton<ChatRepositoryImpl>(
          () => ChatRepositoryImpl(
            connection: scope<ConnectionManager>(),
            cache: ChatCache(scope<KeyValueStore>(), userId: me.id),
            outbox: Outbox(scope<KeyValueStore>(), userId: me.id),
            me: me,
          ),
          dispose: (repository) => repository.dispose(),
        )
        ..registerLazySingleton<ChatRepository>(
          () => scope<ChatRepositoryImpl>(),
        )
        ..registerFactory<SendMessage>(
          () => SendMessage(scope<ChatRepository>()),
        );
    },
  );

  getIt<ChatRepositoryImpl>().start();
}

Future<void> closeSession() async {
  if (getIt.hasScope(_sessionScope)) {
    await getIt.popScope();
  }
}

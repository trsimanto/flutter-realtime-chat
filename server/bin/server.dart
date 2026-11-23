import 'dart:async';
import 'dart:io';

import 'package:realtime_chat_server/chat_server.dart';

Future<void> main(List<String> args) async {
  final port = _portFromArgs(args) ??
      int.tryParse(Platform.environment['PORT'] ?? '') ??
      8080;

  final server = ChatServer();
  await server.start(port: port);
  stdout.writeln('Chat server listening on ws://0.0.0.0:${server.port}/ws');
  stdout.writeln('Android emulator: ws://10.0.2.2:${server.port}/ws');

  late final StreamSubscription<ProcessSignal> signals;
  signals = ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('Shutting down');
    await signals.cancel();
    await server.close();
    exit(0);
  });
}

int? _portFromArgs(List<String> args) {
  final index = args.indexOf('--port');
  if (index == -1 || index + 1 >= args.length) return null;
  return int.tryParse(args[index + 1]);
}

import 'package:flutter/widgets.dart';
import 'package:realtime_chat/app.dart';
import 'package:realtime_chat/core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const RealtimeChatApp());
}

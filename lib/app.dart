import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/core/di/injection.dart';
import 'package:realtime_chat/core/storage/key_value_store.dart';
import 'package:realtime_chat/core/theme/app_theme.dart';
import 'package:realtime_chat/data/local/session_store.dart';
import 'package:realtime_chat/presentation/conversations/conversations_page.dart';
import 'package:realtime_chat/presentation/session/session_cubit.dart';
import 'package:realtime_chat/presentation/sign_in/sign_in_page.dart';
import 'package:realtime_chat/presentation/theme/theme_cubit.dart';

class RealtimeChatApp extends StatelessWidget {
  const RealtimeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit(getIt<KeyValueStore>())),
        BlocProvider(
          create: (_) => SessionCubit(
            store: getIt<SessionStore>(),
            onSignIn: openSession,
            onSignOut: closeSession,
          )..restore(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp(
          title: 'Realtime Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: BlocBuilder<SessionCubit, SessionState>(
            builder: (context, state) => switch (state) {
              SessionLoading() => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              SignedOut() => const SignInPage(),
              SignedIn(:final session) => ConversationsPage(
                  key: ValueKey(session),
                  session: session,
                ),
            },
          ),
        ),
      ),
    );
  }
}

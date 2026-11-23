import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/domain/entities/session.dart';
import 'package:realtime_chat/presentation/session/session_cubit.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _name = TextEditingController();
  final _url = TextEditingController(text: _defaultServerUrl());
  ChatMode _mode = ChatMode.demo;
  bool _busy = false;

  /// The Android emulator reaches the host machine through 10.0.2.2.
  static String _defaultServerUrl() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'ws://10.0.2.2:8080/ws'
          : 'ws://localhost:8080/ws';

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  bool get _canContinue {
    if (_busy || Session.slugFor(_name.text).isEmpty) return false;
    if (_mode == ChatMode.demo) return true;
    final uri = Uri.tryParse(_url.text.trim());
    return uri != null && (uri.scheme == 'ws' || uri.scheme == 'wss');
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    final session = Session(
      userId: Session.slugFor(name),
      displayName: name,
      mode: _mode,
      serverUrl: _mode == ChatMode.server ? _url.text.trim() : '',
    );
    final cubit = context.read<SessionCubit>();
    setState(() => _busy = true);
    try {
      await cubit.signIn(session);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.forum_rounded, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Realtime Chat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'WebSocket messaging with typing indicators, read '
                    'receipts and an offline outbox.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_canContinue) _continue();
                    },
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ChatMode>(
                    segments: const [
                      ButtonSegment(
                        value: ChatMode.demo,
                        label: Text('Demo'),
                        icon: Icon(Icons.smart_toy_outlined),
                      ),
                      ButtonSegment(
                        value: ChatMode.server,
                        label: Text('Local server'),
                        icon: Icon(Icons.dns_outlined),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) =>
                        setState(() => _mode = selection.first),
                  ),
                  const SizedBox(height: 16),
                  if (_mode == ChatMode.server)
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        helperText: 'Android emulator: ws://10.0.2.2:8080/ws',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  else
                    Text(
                      'Chat with simulated contacts. No server needed.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _canContinue ? _continue : null,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

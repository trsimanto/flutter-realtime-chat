import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/data/local/session_store.dart';
import 'package:realtime_chat/domain/entities/session.dart';

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => const [];
}

final class SessionLoading extends SessionState {
  const SessionLoading();
}

final class SignedOut extends SessionState {
  const SignedOut();
}

final class SignedIn extends SessionState {
  const SignedIn(this.session);

  final Session session;

  @override
  List<Object?> get props => [session];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required SessionStore store,
    required Future<void> Function(Session session) onSignIn,
    required Future<void> Function() onSignOut,
  })  : _store = store,
        _onSignIn = onSignIn,
        _onSignOut = onSignOut,
        super(const SessionLoading());

  final SessionStore _store;
  final Future<void> Function(Session session) _onSignIn;
  final Future<void> Function() _onSignOut;

  Future<void> restore() async {
    final session = _store.load();
    if (session == null) {
      emit(const SignedOut());
      return;
    }
    await _onSignIn(session);
    emit(SignedIn(session));
  }

  Future<void> signIn(Session session) async {
    await _store.save(session);
    await _onSignIn(session);
    emit(SignedIn(session));
  }

  Future<void> signOut() async {
    emit(const SignedOut());
    await _onSignOut();
    await _store.clear();
  }
}

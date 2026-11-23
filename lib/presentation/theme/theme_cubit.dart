import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_chat/core/storage/key_value_store.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._store) : super(_read(_store));

  static const _key = 'theme_mode';

  final KeyValueStore _store;

  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    emit(next);
    unawaited(_store.setString(_key, next.name));
  }

  static ThemeMode _read(KeyValueStore store) {
    final value = store.getString(_key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }
}

// Recreates the Android and iOS folders and applies the project settings
// that `flutter create` does not know about.
//
//   dart run tool/bootstrap.dart
import 'dart:io';

const _applicationId = 'dev.towhid.realtimechat';

Future<void> main() async {
  final create = await Process.start(
    'flutter',
    [
      'create',
      '--org',
      'dev.towhid',
      '--project-name',
      'realtime_chat',
      '--platforms',
      'android,ios',
      '.',
    ],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final code = await create.exitCode;
  if (code != 0) exit(code);

  for (final path in [
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
  ]) {
    _edit(
      path,
      (text) => text.replaceAll(
        RegExp(r'applicationId\s*=?\s*"[^"]+"'),
        'applicationId = "$_applicationId"',
      ),
    );
  }

  _edit('ios/Runner.xcodeproj/project.pbxproj', (text) {
    return text.replaceAll('dev.towhid.realtimeChat', _applicationId);
  });

  // Release builds need the permission explicitly; debug builds get it from
  // the debug manifest.
  _edit('android/app/src/main/AndroidManifest.xml', (text) {
    const permission =
        '<uses-permission android:name="android.permission.INTERNET"/>';
    if (text.contains('android.permission.INTERNET')) return text;
    return text.replaceFirstMapped(
      RegExp(r'<manifest[^>]*>'),
      (match) => '${match[0]}\n    $permission',
    );
  });

  stdout.writeln('Platform folders ready (application id $_applicationId).');
}

void _edit(String path, String Function(String text) change) {
  final file = File(path);
  if (!file.existsSync()) return;
  final before = file.readAsStringSync();
  final after = change(before);
  if (after != before) {
    file.writeAsStringSync(after);
    stdout.writeln('Updated $path');
  }
}

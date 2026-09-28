// The browser build as it is deployed: `dart run tool/build_web.dart` from
// app/ (firebase.json runs it before every hosting deploy). Extra arguments
// go to `flutter build web`, e.g. --dart-define=API_BASE_URL=...
//
// Three things a plain `flutter build web` does not do:
//
// - --wasm: Dart compiled to WebAssembly with the skwasm renderer, which
//   starts faster and blocks the main thread far less than main.dart.js.
//   Browsers without WasmGC get the JavaScript build, which is built too.
// - The KaTeX fonts come out of assets/FontManifest.json, so the engine does
//   not fetch all 22 before the first frame; the app loads them when it
//   first draws a formula (lib/ui/widgets/katex_fonts.dart).
// - The dangling flutter.js.map reference is removed (see the end of main).

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final build = await Process.start(
    'flutter',
    ['build', 'web', '--release', '--wasm', ...args],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await build.exitCode;
  if (code != 0) exit(code);

  final manifest = File('build/web/assets/FontManifest.json');
  final families = (jsonDecode(manifest.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final kept = [
    for (final f in families)
      if (!(f['family'] as String).startsWith('packages/flutter_math_fork/')) f,
  ];
  manifest.writeAsStringSync(jsonEncode(kept));
  stdout.writeln('FontManifest.json: ${families.length - kept.length} KaTeX families left to load on first use.');

  // flutter.js, and flutter_bootstrap.js which inlines it, point at a
  // flutter.js.map that the build does not produce. Hosting's SPA rewrite
  // answers that request with index.html, which devtools and Lighthouse
  // then fail to parse as a source map.
  for (final name in ['flutter.js', 'flutter_bootstrap.js']) {
    final file = File('build/web/$name');
    file.writeAsStringSync(
      file.readAsStringSync().replaceAll('//# sourceMappingURL=flutter.js.map', ''),
    );
  }
}

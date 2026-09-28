// The KaTeX fonts flutter_math_fork draws formulas with, loaded on first use
// in the browser build.
//
// The package declares 22 of them (about 600 KB), and Flutter web fetches
// every font in FontManifest.json before it draws the first frame, though
// most reports hold no maths. tool/build_web.dart takes them out of the web
// build's manifest; this registers them the first time a formula is shown.
// Android loads fonts on demand anyway, so it keeps the manifest as it is.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The families, as flutter_math_fork names them in its TextStyles, and the
/// files of each. Keep in step with the package's pubspec and with
/// tool/build_web.dart.
const katexFonts = {
  'KaTeX_Main': ['Main-Regular', 'Main-Italic', 'Main-Bold', 'Main-BoldItalic'],
  'KaTeX_Math': ['Math-Italic', 'Math-BoldItalic'],
  'KaTeX_AMS': ['AMS-Regular'],
  'KaTeX_Caligraphic': ['Caligraphic-Regular', 'Caligraphic-Bold'],
  'KaTeX_Fraktur': ['Fraktur-Regular', 'Fraktur-Bold'],
  'KaTeX_SansSerif': ['SansSerif-Regular', 'SansSerif-Bold', 'SansSerif-Italic'],
  'KaTeX_Script': ['Script-Regular'],
  'KaTeX_Typewriter': ['Typewriter-Regular'],
  'KaTeX_Size1': ['Size1-Regular'],
  'KaTeX_Size2': ['Size2-Regular'],
  'KaTeX_Size3': ['Size3-Regular'],
  'KaTeX_Size4': ['Size4-Regular'],
};

bool _ready = !kIsWeb;
Future<void>? _loading;

/// Whether formulas can be drawn now, without waiting for [loadKatexFonts].
bool get katexFontsReady => _ready;

/// Registers the fonts once. A font that fails to load leaves its formulas
/// in a fallback face rather than never drawn, so this always completes.
Future<void> loadKatexFonts() => _loading ??= _load();

Future<void> _load() async {
  if (_ready) return;
  await Future.wait([
    for (final MapEntry(key: family, value: files) in katexFonts.entries)
      (FontLoader('packages/flutter_math_fork/$family')..addFonts(files)).load().catchError((Object e) {
        debugPrint('KaTeX font $family did not load: $e');
      }),
  ]);
  _ready = true;
}

extension on FontLoader {
  void addFonts(List<String> files) {
    for (final file in files) {
      addFont(rootBundle.load('packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_$file.ttf'));
    }
  }
}

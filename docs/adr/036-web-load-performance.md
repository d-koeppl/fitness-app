# ADR-036 — The browser build: WebAssembly, a loading screen, KaTeX fonts on first use

**Status:** Accepted · **Date:** 2026-09-28

## Context

A Lighthouse mobile run on fitness.koeppl.cc scored Performance 0.29
(simulated FCP 26 s, LCP 61 s, TBT 1,540 ms). Most of that is the cost of
Flutter's CanvasKit renderer: 5.4 MB of `canvaskit.wasm` and 4 MB of
`main.dart.js`, which Lighthouse throttles to a slow 4G link and a slow CPU.
The page painted nothing until the engine had downloaded and drawn its first
frame. Before that frame the engine also fetched every font in
`FontManifest.json`, including the 22 KaTeX fonts that `flutter_math_fork`
declares (about 600 KB over 22 requests), though most reports hold no maths.
`/robots.txt` and `/llms.txt` answered with `index.html` through the
hosting rewrite, which cost the SEO and agentic scores.

## Decision

- **The deployed build is `dart run tool/build_web.dart`** (from `app/`),
  and `firebase.json` runs it as the hosting predeploy step. It builds with
  `--wasm`, which uses dart2wasm and the skwasm renderer, so there is less
  main-thread work at start-up. Browsers without WasmGC load the JavaScript
  build, which is built alongside. No COOP/COEP headers are set: they would
  get in the way of the Google and Firebase sign-in popups, so skwasm runs
  single-threaded.
- **The KaTeX fonts load on first use.** The build script takes them out of
  the web build's `FontManifest.json`. `lib/ui/widgets/katex_fonts.dart`
  registers them with `FontLoader` the first time a formula is drawn, and
  shows the formula's source until they are ready. Android keeps the
  manifest as it is, because it loads fonts on demand anyway. A web build
  made without the script still works; it just fetches the fonts up front
  again.
- **`index.html` has a loading screen in plain HTML** (the icon and the
  name). Flutter's view covers it, and it is removed on the engine's
  `flutter-first-frame` event. First paint happens as soon as the HTML
  arrives.
- **`web/robots.txt` disallows everything** (every page needs a sign-in),
  and `web/llms.txt` says what the site is.

## Consequences

- Lighthouse's Performance score stays well short of green: CanvasKit or
  skwasm is still megabytes before the app's own code runs.
- Math in a report shows as TeX source for a moment the first time the
  browser build draws one.
- The KaTeX family list lives in `katex_fonts.dart` and must follow
  `flutter_math_fork`'s pubspec when the package is upgraded.
- A hosting deploy now builds the app first, so it takes about a minute
  longer.
- The deprecated `Intl.v8BreakIterator` warning comes from the Flutter
  engine and stays until an engine release drops it.

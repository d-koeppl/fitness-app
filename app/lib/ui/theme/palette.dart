// The design tokens of fitness-dashboard's web/app/globals.css and
// web/lib/tone.ts, as Dart.
//
// The web derives every role from a handful of seeds with CSS color-mix();
// [mix] is the same operation, so each token below reads like its CSS line
// and light/dark stay one table apart. Widgets read colours from
// `Palette.of(context)`, never from literals.

import 'package:flutter/material.dart';

import '../../domain/key_metrics.dart';

const _seedPrimary = Color(0xFF0B57D0);
const _seedSecondary = Color(0xFF535F70);
const _seedTertiary = Color(0xFF7C4DCC);
const _seedError = Color(0xFFB3261E);
const _seedSuccess = Color(0xFF1E8E3E);
const _seedWarning = Color(0xFFE0821C);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

/// CSS `color-mix(in srgb, a p%, b)`.
Color mix(Color a, double percent, Color b) => Color.lerp(b, a, percent / 100)!;

/// One M3 role expanded into its four colours.
class Role {
  const Role(this.color, this.on, this.container, this.onContainer);

  final Color color;
  final Color on;
  final Color container;
  final Color onContainer;
}

/// A tonal tile's colours (web/lib/tone.ts): its background, the progress
/// fill, the text, the disc behind the icon, and the icon.
class Tone {
  const Tone({required this.bg, required this.fill, required this.fg, required this.chip, required this.icon});

  final Color bg;
  final Color fill;
  final Color fg;
  final Color chip;
  final Color icon;
}

/// A chip's background and text colour.
class ChipTone {
  const ChipTone(this.bg, this.fg);

  final Color bg;
  final Color fg;
}

@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
    required this.success,
    required this.warning,
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
  });

  final Role primary;
  final Role secondary;
  final Role tertiary;
  final Role error;
  final Role success;
  final Role warning;

  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  static final light = Palette(
    primary: Role(_seedPrimary, _white, mix(_seedPrimary, 16, _white), mix(_seedPrimary, 78, _black)),
    secondary: Role(_seedSecondary, _white, mix(_seedSecondary, 16, _white), mix(_seedSecondary, 70, _black)),
    tertiary: Role(_seedTertiary, _white, mix(_seedTertiary, 18, _white), mix(_seedTertiary, 72, _black)),
    error: Role(_seedError, _white, mix(_seedError, 18, _white), mix(_seedError, 74, _black)),
    success: Role(_seedSuccess, _white, mix(_seedSuccess, 18, _white), mix(_seedSuccess, 76, _black)),
    warning: Role(_seedWarning, _white, mix(_seedWarning, 20, _white), mix(_seedWarning, 74, _black)),
    surface: mix(_seedPrimary, 2, _white),
    surfaceContainerLowest: _white,
    surfaceContainerLow: mix(_seedPrimary, 3.5, _white),
    surfaceContainer: mix(_seedPrimary, 6, _white),
    surfaceContainerHigh: mix(_seedPrimary, 9, _white),
    surfaceContainerHighest: mix(_seedPrimary, 12, _white),
    onSurface: const Color(0xFF1B1C1E),
    onSurfaceVariant: const Color(0xFF44474A),
    outline: const Color(0xFF74777A),
    outlineVariant: const Color(0xFFC4C7CA),
  );

  static final dark = Palette(
    primary: Role(
      mix(_seedPrimary, 65, _white),
      mix(_seedPrimary, 30, _black),
      mix(_seedPrimary, 48, _black),
      mix(_seedPrimary, 22, _white),
    ),
    secondary: Role(
      mix(_seedSecondary, 70, _white),
      mix(_seedSecondary, 82, _black),
      mix(_seedSecondary, 40, _black),
      mix(_seedSecondary, 18, _white),
    ),
    tertiary: Role(
      mix(_seedTertiary, 68, _white),
      mix(_seedTertiary, 82, _black),
      mix(_seedTertiary, 46, _black),
      mix(_seedTertiary, 20, _white),
    ),
    error: Role(
      mix(_seedError, 70, _white),
      mix(_seedError, 82, _black),
      mix(_seedError, 42, _black),
      mix(_seedError, 20, _white),
    ),
    success: Role(
      mix(_seedSuccess, 68, _white),
      mix(_seedSuccess, 82, _black),
      mix(_seedSuccess, 42, _black),
      mix(_seedSuccess, 20, _white),
    ),
    warning: Role(
      mix(_seedWarning, 68, _white),
      mix(_seedWarning, 82, _black),
      mix(_seedWarning, 42, _black),
      mix(_seedWarning, 20, _white),
    ),
    surface: const Color(0xFF121316),
    surfaceContainerLowest: const Color(0xFF0C0D0F),
    surfaceContainerLow: const Color(0xFF1A1B1E),
    surfaceContainer: const Color(0xFF1E2023),
    surfaceContainerHigh: const Color(0xFF292A2E),
    surfaceContainerHighest: const Color(0xFF333439),
    onSurface: const Color(0xFFE3E2E6),
    onSurfaceVariant: const Color(0xFFC4C6CA),
    outline: const Color(0xFF8E9094),
    outlineVariant: const Color(0xFF44474A),
  );

  // --- web/lib/tone.ts ---------------------------------------------------

  Tone get slate => Tone(
    bg: secondary.container,
    fill: mix(secondary.color, 30, secondary.container),
    fg: secondary.onContainer,
    chip: surfaceContainerLowest,
    icon: success.color,
  );

  Tone get sleep => Tone(
    bg: tertiary.container,
    fill: mix(tertiary.color, 35, tertiary.container),
    fg: tertiary.onContainer,
    chip: surfaceContainerLowest,
    icon: tertiary.color,
  );

  Tone get weight => Tone(
    bg: primary.container,
    fill: mix(primary.color, 30, primary.container),
    fg: primary.onContainer,
    chip: surfaceContainerLowest,
    icon: primary.color,
  );

  Tone get mint => Tone(
    bg: mix(success.color, 40, success.container),
    fill: mix(success.color, 70, success.container),
    fg: success.onContainer,
    chip: surfaceContainerLowest,
    icon: success.onContainer,
  );

  Tone get flame => Tone(
    bg: warning.container,
    fill: mix(warning.color, 35, warning.container),
    fg: warning.onContainer,
    chip: surfaceContainerLowest,
    icon: warning.color,
  );

  /// The report's readiness chip.
  ChipTone readyTone(String? readiness) => switch (readiness) {
    'high' => ChipTone(success.container, success.onContainer),
    'moderate' => ChipTone(warning.container, warning.onContainer),
    'low' => ChipTone(error.container, error.onContainer),
    _ => ChipTone(surfaceContainerHigh, onSurfaceVariant),
  };

  /// Garmin-style training-status labels (api/analysis/training_load.py).
  ({String label, ChipTone tone}) statusTone(String status) => switch (status) {
    'productive' => (label: 'Productive', tone: ChipTone(success.container, success.onContainer)),
    'peaking' => (label: 'Peaking', tone: ChipTone(success.container, success.onContainer)),
    'recovery' => (label: 'Recovery', tone: ChipTone(tertiary.container, tertiary.onContainer)),
    'strained' => (label: 'Strained', tone: ChipTone(warning.container, warning.onContainer)),
    'overreaching' => (label: 'Overreaching', tone: ChipTone(error.container, error.onContainer)),
    'detraining' => (label: 'Detraining', tone: ChipTone(surfaceContainerHigh, onSurfaceVariant)),
    'insufficient_data' => (label: 'Not enough data', tone: ChipTone(surfaceContainerHigh, onSurfaceVariant)),
    _ => (label: 'Maintaining', tone: ChipTone(primary.container, primary.onContainer)),
  };

  /// Win, draw, loss and unknown badges.
  ChipTone outcomeTone(String letter) => switch (letter) {
    'W' => ChipTone(success.container, success.onContainer),
    'D' => ChipTone(warning.container, warning.onContainer),
    'L' => ChipTone(error.container, error.onContainer),
    _ => ChipTone(surfaceContainerHigh, onSurfaceVariant),
  };

  Color get fitnessColor => primary.color;
  Color get fatigueColor => warning.color;

  /// A metric's line colour.
  Color hue(MetricHue hue) => switch (hue) {
    MetricHue.success => success.color,
    MetricHue.successTertiary => mix(success.color, 70, tertiary.color),
    MetricHue.tertiary => tertiary.color,
    MetricHue.primary => primary.color,
    MetricHue.secondary => secondary.color,
    MetricHue.warning => warning.color,
  };

  /// A metric's band: the container of its role.
  Color band(MetricHue hue) => switch (hue) {
    MetricHue.success || MetricHue.successTertiary => success.container,
    MetricHue.tertiary => tertiary.container,
    MetricHue.primary => primary.container,
    MetricHue.secondary => secondary.container,
    MetricHue.warning => warning.container,
  };

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The M3 type scale of globals.css, size / line height / weight / tracking.
abstract final class TypeScale {
  static TextStyle _s(double size, double height, FontWeight weight, double tracking) =>
      TextStyle(fontSize: size, height: height / size, fontWeight: weight, letterSpacing: tracking);

  static final headlineMedium = _s(28, 34, FontWeight.w700, -0.3);
  static final headlineSmall = _s(24, 30, FontWeight.w600, -0.2);
  static final titleLarge = _s(22, 28, FontWeight.w500, -0.2);
  static final titleMedium = _s(16, 22, FontWeight.w600, 0.1);
  static final titleSmall = _s(14, 20, FontWeight.w600, 0.1);
  static final bodyLarge = _s(16, 24, FontWeight.w400, 0.15);
  static final bodyMedium = _s(14, 20, FontWeight.w400, 0.15);
  static final bodySmall = _s(12, 16, FontWeight.w400, 0.2);
  static final labelLarge = _s(14, 20, FontWeight.w600, 0.1);
  static final labelMedium = _s(12, 16, FontWeight.w600, 0.3);
  static final labelSmall = _s(11, 15, FontWeight.w600, 0.3);

  /// Digits of equal width, so numbers do not jitter as they change.
  static const tabular = [FontFeature.tabularFigures()];
}

/// Corner radii (globals.css shape scale).
abstract final class Shape {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 28.0;
}

ThemeData buildTheme(Palette p, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary.color,
    onPrimary: p.primary.on,
    primaryContainer: p.primary.container,
    onPrimaryContainer: p.primary.onContainer,
    secondary: p.secondary.color,
    onSecondary: p.secondary.on,
    secondaryContainer: p.secondary.container,
    onSecondaryContainer: p.secondary.onContainer,
    tertiary: p.tertiary.color,
    onTertiary: p.tertiary.on,
    tertiaryContainer: p.tertiary.container,
    onTertiaryContainer: p.tertiary.onContainer,
    error: p.error.color,
    onError: p.error.on,
    errorContainer: p.error.container,
    onErrorContainer: p.error.onContainer,
    surface: p.surface,
    onSurface: p.onSurface,
    onSurfaceVariant: p.onSurfaceVariant,
    surfaceContainerLowest: p.surfaceContainerLowest,
    surfaceContainerLow: p.surfaceContainerLow,
    surfaceContainer: p.surfaceContainer,
    surfaceContainerHigh: p.surfaceContainerHigh,
    surfaceContainerHighest: p.surfaceContainerHighest,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // The page sits at "container"; cards sit above it at "surface".
    scaffoldBackgroundColor: p.surfaceContainer,
    extensions: [p],
  );
}

// One metric's chart in its three styles (HeroStyle) — the Health tab's
// featured chart and, with a crosshair, the detail sheet's — and the range
// track each list row carries. Painted directly rather than with fl_chart,
// which cannot draw the band or the smoothed wash. Charts of several series
// (training load, the coach's) stay on MetricChart.
//
// A gap in the data breaks the line, as in MetricChart: the watch was off,
// and drawing across it would invent readings.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/health_chart.dart';
import '../../domain/series.dart';
import '../theme/palette.dart';

/// Room on the right for the y-axis labels, and under the plot for the dates.
const _gutter = 36.0;
const _xBand = 22.0;
const _padTop = 14.0;

class HealthChart extends StatelessWidget {
  const HealthChart({
    super.key,
    required this.style,
    required this.values,
    required this.labels,
    required this.color,
    required this.formatTick,
    required this.minStep,
    this.domain,
    this.normal,
    this.better,
    this.active,
    this.onActiveChange,
    required this.semanticLabel,
  });

  final HeroStyle style;
  final List<num?> values;

  /// One per value; null where no date is written.
  final List<String?> labels;
  final Color color;
  final String Function(num value) formatTick;
  final double minStep;

  /// A pinned y-axis, for the 0–100 scores.
  final (double, double)? domain;

  /// The band [HeroStyle.band] draws; without one it draws a plain line.
  final NormalRange? normal;

  /// Which side of [normal] is good; days on the other side are warnings.
  final Better? better;

  /// The value under the crosshair. Without [onActiveChange] the chart is a
  /// picture and has none.
  final int? active;
  final ValueChanged<int?>? onActiveChange;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Taller for its width on a phone or in a sheet, where a flat plot
          // would squash the shape into a few pixels.
          final height = (width * (width < 600 ? 0.5 : 0.34)).clamp(170.0, 250.0);
          final chart = CustomPaint(
            size: Size(width, height),
            painter: _HealthChartPainter(
              style: style,
              values: values,
              labels: labels,
              color: color,
              formatTick: formatTick,
              minStep: minStep,
              domain: domain,
              normal: normal,
              better: better,
              active: active,
              palette: p,
              textStyle: TypeScale.labelSmall.copyWith(fontFeatures: TypeScale.tabular),
            ),
          );
          final onActive = onActiveChange;
          if (onActive == null || values.isEmpty) return chart;

          // The pointer only has to be over a value's slot, not on its mark.
          final slot = (width - _gutter) / values.length;
          int indexAt(Offset position) => (position.dx / slot).floor().clamp(0, values.length - 1);
          return MouseRegion(
            onHover: (event) => onActive(indexAt(event.localPosition)),
            onExit: (_) => onActive(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final i = indexAt(details.localPosition);
                onActive(i == active ? null : i);
              },
              // Horizontal only, so the sheet still scrolls vertically.
              onHorizontalDragStart: (details) => onActive(indexAt(details.localPosition)),
              onHorizontalDragUpdate: (details) => onActive(indexAt(details.localPosition)),
              child: chart,
            ),
          );
        },
      ),
    );
  }
}

class _HealthChartPainter extends CustomPainter {
  _HealthChartPainter({
    required this.style,
    required this.values,
    required this.labels,
    required this.color,
    required this.formatTick,
    required this.minStep,
    required this.domain,
    required this.normal,
    required this.better,
    required this.active,
    required this.palette,
    required this.textStyle,
  });

  final HeroStyle style;
  final List<num?> values;
  final List<String?> labels;
  final Color color;
  final String Function(num value) formatTick;
  final double minStep;
  final (double, double)? domain;
  final NormalRange? normal;
  final Better? better;
  final int? active;
  final Palette palette;
  final TextStyle textStyle;

  /// The value the chart points at: the one under the crosshair, else the
  /// newest reading.
  int get _focus => active ?? values.lastIndexWhere((v) => v != null);

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final bars = style == HeroStyle.bars;
    final band = style == HeroStyle.band ? normal : null;
    // A heart metric with no normal yet (too few readings, or averaged
    // weeks the daily band does not describe) reads as a plain level.
    final drawn = style == HeroStyle.band && band == null ? HeroStyle.area : style;
    final nums = values.whereType<num>().toList();
    final scale = niceScale(
      [
        ...nums,
        if (band != null) ...[band.lo, band.hi],
      ],
      zeroBased: bars,
      minStep: minStep,
      domain: domain,
      targetTicks: domain != null ? 3 : 4,
    );

    // Headroom for the values written over a week of bars.
    final labelled = bars && n <= 7;
    final plot = Rect.fromLTRB(0, _padTop + (labelled ? 16 : 0), size.width - _gutter, size.height - _xBand);
    double y(num v) => plot.bottom - (v - scale.lo) / (scale.hi - scale.lo) * plot.height;
    // Bars sit in slots; points sit at the slot centres, so a week of either
    // lines up with its labels the same way.
    final slot = plot.width / n;
    double x(int i) => plot.left + slot * (i + 0.5);

    // Grid and y labels, hairline and behind everything.
    final grid = Paint()
      ..color = palette.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final t in scale.ticks) {
      final ty = y(t);
      canvas.drawLine(Offset(plot.left, ty), Offset(plot.right, ty), grid);
      _text(canvas, formatTick(t), Offset(size.width, ty), palette.onSurfaceVariant, align: _Align.rightMiddle);
    }

    // The crosshair: readers aim at a date, not at a 2px line.
    if (active != null) {
      canvas.drawLine(
        Offset(x(active!), plot.top),
        Offset(x(active!), plot.bottom),
        Paint()
          ..color = palette.outline
          ..strokeWidth = 1,
      );
    }

    // Dates under the plot; the one pointed at stands out.
    final focusLabel = active ?? n - 1;
    for (final (i, label) in labels.indexed) {
      if (label == null) continue;
      final last = i == focusLabel;
      _text(
        canvas,
        label,
        Offset(x(i), size.height - _xBand / 2 + 2),
        last ? palette.onSurface : palette.onSurfaceVariant,
        align: _Align.centre,
        bold: last,
      );
    }

    if (nums.isEmpty) return;
    final mean = nums.reduce((a, b) => a + b) / nums.length;

    // The range's average, dashed and behind the data, so it reads as a
    // reference and not as data; its tag goes on top so nothing hides it.
    final my = band == null ? y(mean) : null;
    if (my != null) {
      _dashed(canvas, Offset(plot.left, my), Offset(plot.right, my), palette.onSurfaceVariant.withValues(alpha: 0.6));
    }

    switch (drawn) {
      case HeroStyle.bars:
        _paintBars(canvas, plot, slot, x, y);
      case HeroStyle.area:
        _paintArea(canvas, plot, x, y);
      case HeroStyle.band:
        _paintBand(canvas, plot, x, y, band);
    }

    if (my != null) {
      // Under the line beside bars, where it cannot land on a bar's value.
      _text(
        canvas,
        'avg',
        Offset(plot.left + 4, bars ? my + 4 : my),
        palette.onSurfaceVariant,
        align: bars ? _Align.leftTop : _Align.leftMiddle,
        background: palette.surfaceContainerHigh,
      );
    }
  }

  void _paintBars(Canvas canvas, Rect plot, double slot, double Function(int) x, double Function(num) y) {
    final width = math.min(slot * 0.62, 44.0);
    final n = values.length;
    final focus = _focus;
    for (final (i, v) in values.indexed) {
      if (v == null) continue;
      final last = i == focus;
      final top = math.min(y(v), plot.bottom - width / 2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x(i) - width / 2, top, x(i) + width / 2, plot.bottom),
        Radius.circular(math.min(width / 2, 12)),
      );
      canvas.drawRRect(rect, Paint()..color = last ? color : color.withValues(alpha: 0.3));
      // A value over each bar while there is room for it.
      if (n <= 7) {
        _text(
          canvas,
          formatTick(v),
          Offset(x(i), top - 4),
          last ? palette.onSurface : palette.onSurfaceVariant,
          align: _Align.centreBottom,
          bold: last,
          background: palette.surface,
        );
      }
    }
  }

  void _paintArea(Canvas canvas, Rect plot, double Function(int) x, double Function(num) y) {
    final runs = _runs(x, y);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final wash = Paint()
      ..shader = ui.Gradient.linear(Offset(0, plot.top), Offset(0, plot.bottom), [
        color.withValues(alpha: 0.26),
        color.withValues(alpha: 0),
      ]);
    for (final run in runs) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 3.5, Paint()..color = color);
        continue;
      }
      final line = _monotone(run);
      final area = Path.from(line)
        ..lineTo(run.last.dx, plot.bottom)
        ..lineTo(run.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(area, wash);
      canvas.drawPath(line, stroke);
    }
    _pointed(canvas, x, y, color);
  }

  void _paintBand(Canvas canvas, Rect plot, double Function(int) x, double Function(num) y, NormalRange? band) {
    final warn = palette.warning.color;
    if (band != null) {
      final rect = Rect.fromLTRB(plot.left, y(band.hi), plot.right, y(band.lo));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: 0.1),
      );
      final edge = color.withValues(alpha: 0.35);
      _dashed(canvas, rect.topLeft, rect.topRight, edge);
      _dashed(canvas, rect.bottomLeft, rect.bottomRight, edge);
      _text(
        canvas,
        'Normal ${formatTick(band.lo)}–${formatTick(band.hi)}',
        Offset(rect.left + 8, rect.bottom - 4),
        color,
        align: _Align.leftBottom,
        bold: true,
        background: palette.surface.withValues(alpha: 0.85),
      );
    }

    final line = Paint()
      ..color = palette.onSurface.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final run in _runs(x, y)) {
      if (run.length < 2) continue;
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final pt in run.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, line);
    }

    // Days outside the band are what this chart is for, on the good side
    // as much as the bad; past a month the days inside are left to the line.
    Verdict verdict(num v) => band == null ? Verdict.usual : verdictFor(bandStatus(band, v), better);
    final n = values.length;
    for (final (i, v) in values.indexed) {
      if (v == null || i == _focus) continue;
      final at = Offset(x(i), y(v));
      switch (verdict(v)) {
        case Verdict.worse:
          canvas.drawCircle(at, 4.5, Paint()..color = warn);
        case Verdict.better:
          // As big as a warning, ringed so it reads apart from the band's
          // own dots in the same colour.
          canvas.drawCircle(at, 6, Paint()..color = palette.surface);
          canvas.drawCircle(at, 4.5, Paint()..color = color);
        case Verdict.usual:
          if (n <= 31) canvas.drawCircle(at, 3, Paint()..color = color);
      }
    }
    final focus = _focus < 0 ? null : values[_focus];
    _pointed(canvas, x, y, focus != null && verdict(focus) == Verdict.worse ? warn : color);
  }

  /// The value pointed at: a ringed dot in a soft halo.
  void _pointed(Canvas canvas, double Function(int) x, double Function(num) y, Color c) {
    final i = _focus;
    final v = i < 0 ? null : values[i];
    if (v == null) return;
    final at = Offset(x(i), y(v));
    canvas.drawCircle(at, 11, Paint()..color = c.withValues(alpha: 0.18));
    canvas.drawCircle(at, 6.5, Paint()..color = palette.surface);
    canvas.drawCircle(at, 4.5, Paint()..color = c);
  }

  /// The points split at every missing day.
  List<List<Offset>> _runs(double Function(int) x, double Function(num) y) {
    final runs = <List<Offset>>[];
    var current = <Offset>[];
    for (final (i, v) in values.indexed) {
      if (v == null) {
        if (current.isNotEmpty) runs.add(current);
        current = [];
      } else {
        current.add(Offset(x(i), y(v)));
      }
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color c) {
    final paint = Paint()
      ..color = c
      ..strokeWidth = 1.25;
    const dash = 3.0, gap = 5.0;
    final length = (b - a).distance;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color c, {
    required _Align align,
    bool bold = false,
    Color? background,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: c, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = switch (align) {
      _Align.rightMiddle => at - Offset(painter.width, painter.height / 2),
      _Align.centre => at - Offset(painter.width / 2, painter.height / 2),
      _Align.centreBottom => at - Offset(painter.width / 2, painter.height),
      _Align.leftBottom => at - Offset(0, painter.height),
      _Align.leftMiddle => at - Offset(-4, painter.height / 2),
      _Align.leftTop => at + const Offset(4, 0),
    };
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(offset.dx - 4, offset.dy - 1, painter.width + 8, painter.height + 2),
          const Radius.circular(6),
        ),
        Paint()..color = background,
      );
    }
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_HealthChartPainter old) =>
      old.style != style ||
      old.values != values ||
      old.labels != labels ||
      old.color != color ||
      old.normal != normal ||
      old.better != better ||
      old.active != active ||
      old.palette != palette;
}

enum _Align { rightMiddle, centre, centreBottom, leftBottom, leftMiddle, leftTop }

/// A smooth curve through [pts] that never overshoots them (Fritsch–Carlson
/// monotone cubic): a smoothed line must not draw a peak that was not there.
Path _monotone(List<Offset> pts) {
  final n = pts.length;
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (n == 2) return path..lineTo(pts[1].dx, pts[1].dy);
  final slopes = [for (var i = 0; i < n - 1; i++) (pts[i + 1].dy - pts[i].dy) / (pts[i + 1].dx - pts[i].dx)];
  final t = List<double>.filled(n, 0);
  t[0] = slopes.first;
  t[n - 1] = slopes.last;
  for (var i = 1; i < n - 1; i++) {
    t[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (slopes[i] == 0) {
      t[i] = 0;
      t[i + 1] = 0;
      continue;
    }
    final a = t[i] / slopes[i], b = t[i + 1] / slopes[i];
    final s = a * a + b * b;
    if (s > 9) {
      final tau = 3 / math.sqrt(s);
      t[i] = tau * a * slopes[i];
      t[i + 1] = tau * b * slopes[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final dx = (pts[i + 1].dx - pts[i].dx) / 3;
    path.cubicTo(
      pts[i].dx + dx,
      pts[i].dy + t[i] * dx,
      pts[i + 1].dx - dx,
      pts[i + 1].dy - t[i + 1] * dx,
      pts[i + 1].dx,
      pts[i + 1].dy,
    );
  }
  return path;
}

/// A list row's trend: where the current value sits between the range's low
/// and high, with a tick at its average.
class RangeTrack extends StatelessWidget {
  const RangeTrack({super.key, required this.position, required this.color, required this.formatTick});

  final RangePosition position;
  final Color color;
  final String Function(num value) formatTick;

  static const width = 96.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const dot = 12.0;
    final low = formatTick(position.low), high = formatTick(position.high);
    return Semantics(
      label: 'Range $low to $high',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: dot,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (dot - 6) / 2,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: position.meanPosition * width - 1,
                    top: 0,
                    width: 2,
                    height: dot,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: p.outline, borderRadius: BorderRadius.circular(1)),
                    ),
                  ),
                  Positioned(
                    left: position.position * width - dot / 2,
                    top: 0,
                    width: dot,
                    height: dot,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in [low, high])
                  Text(
                    label,
                    style: TypeScale.labelSmall.copyWith(
                      color: p.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      fontFeatures: TypeScale.tabular,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

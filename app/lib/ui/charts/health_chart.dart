// The app's charts, painted directly rather than with fl_chart, which cannot
// draw the band or the smoothed wash. One series is a metric in its style
// (HeroStyle): the Health tab's featured chart and, with a crosshair, the
// detail sheet's. Several series share one axis: the training sheet's load
// under fitness and fatigue, and the coach's line and bar charts. Also the
// range track each Health list row carries.
//
// A gap in the data breaks the line: the watch was off, and drawing across
// it would invent readings.
//
// Several series never get a second y-axis: two scales on one plot make the
// reader believe a correlation that only comes from where the axes happened
// to line up.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/health_chart.dart';
import '../../domain/key_metrics.dart';
import '../../domain/series.dart';
import '../theme/palette.dart';

/// Room on the right for the y-axis labels, and under the plot for the dates.
const _gutter = 36.0;
const _xBand = 22.0;
const _padTop = 14.0;

/// One series: a value per slot (null where there is none), its colour and
/// its mark.
class HealthSeries {
  const HealthSeries({required this.values, required this.color, this.mark = ChartMark.line, this.smooth = true});

  final List<num?> values;
  final Color color;
  final ChartMark mark;

  /// A line through days is smoothed; one through categories (a coach chart
  /// comparing sessions) is not, since a curve between two categories
  /// suggests values in between that do not exist.
  final bool smooth;
}

class HealthChart extends StatelessWidget {
  const HealthChart({
    super.key,
    required this.series,
    this.style,
    required this.labels,
    required this.formatTick,
    required this.minStep,
    this.domain,
    this.normal,
    this.better,
    this.active,
    this.onActiveChange,
    required this.semanticLabel,
  });

  /// All the same length: they share the x-axis.
  final List<HealthSeries> series;

  /// How a single series is drawn; ignored for several, which are drawn by
  /// their marks. Defaults to what the series' mark suggests.
  final HeroStyle? style;

  /// One per value; null where no label is written.
  final List<String?> labels;
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
    final n = series.isEmpty ? 0 : series.first.values.length;
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
              series: series,
              style: style,
              labels: labels,
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
          if (onActive == null || n == 0) return chart;

          // The pointer only has to be over a value's slot, not on its mark.
          final slot = (width - _gutter) / n;
          int indexAt(Offset position) => (position.dx / slot).floor().clamp(0, n - 1);
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

/// Where the plot is and how values map onto it.
class _Frame {
  _Frame(this.plot, this.n, this.scale);

  final Rect plot;
  final int n;
  final Scale scale;

  double get slot => plot.width / n;

  /// Bars sit in slots; points sit at the slot centres, so a week of either
  /// lines up with its labels the same way.
  double x(int i) => plot.left + slot * (i + 0.5);
  double y(num v) => plot.bottom - (v - scale.lo) / (scale.hi - scale.lo) * plot.height;

  /// Where bars grow from: zero, or the plot's edge when zero is off it.
  double get base => y(0).clamp(plot.top, plot.bottom);
}

class _HealthChartPainter extends CustomPainter {
  _HealthChartPainter({
    required this.series,
    required this.style,
    required this.labels,
    required this.formatTick,
    required this.minStep,
    required this.domain,
    required this.normal,
    required this.better,
    required this.active,
    required this.palette,
    required this.textStyle,
  });

  final List<HealthSeries> series;
  final HeroStyle? style;
  final List<String?> labels;
  final String Function(num value) formatTick;
  final double minStep;
  final (double, double)? domain;
  final NormalRange? normal;
  final Better? better;
  final int? active;
  final Palette palette;
  final TextStyle textStyle;

  /// The canvas's width, for keeping text inside it.
  double _width = double.infinity;

  bool get _single => series.length == 1;

  /// The single series' style; a band without a normal yet (too few
  /// readings, or averaged weeks the daily band does not describe) reads as
  /// a plain level.
  HeroStyle get _style {
    final s = style ?? (series.first.mark == ChartMark.bar ? HeroStyle.bars : HeroStyle.area);
    return s == HeroStyle.band && normal == null ? HeroStyle.area : s;
  }

  /// The slot the chart points at: the one under the crosshair, else the
  /// newest with a reading in any series.
  int get _focus => active ?? series.map((s) => s.values.lastIndexWhere((v) => v != null)).reduce(math.max);

  @override
  void paint(Canvas canvas, Size size) {
    _width = size.width;
    if (series.isEmpty) return;
    final n = series.first.values.length;
    if (n == 0) return;
    final single = _single;
    final hero = single ? _style : null;
    final band = hero == HeroStyle.band ? normal : null;
    final anyBars = series.any((s) => s.mark == ChartMark.bar) || hero == HeroStyle.bars;
    final nums = [
      for (final s in series)
        for (final v in s.values) ?v,
    ];
    final scale = niceScale(
      [
        ...nums,
        if (band != null) ...[band.lo, band.hi],
        // A bar's length is its value, so zero stays on the axis; bars
        // below zero (a coach chart of Form) grow down from it.
        if (anyBars) 0,
      ],
      zeroBased: anyBars && nums.every((v) => v >= 0),
      minStep: minStep,
      domain: domain,
      targetTicks: domain != null ? 3 : 4,
    );

    // Headroom for the values written over a week of bars.
    final labelled = hero == HeroStyle.bars && n <= 7;
    final f = _Frame(
      Rect.fromLTRB(0, _padTop + (labelled ? 16 : 0), size.width - _gutter, size.height - _xBand),
      n,
      scale,
    );

    // Grid and y labels, hairline and behind everything.
    final grid = Paint()
      ..color = palette.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final t in scale.ticks) {
      final ty = f.y(t);
      canvas.drawLine(Offset(f.plot.left, ty), Offset(f.plot.right, ty), grid);
      _text(canvas, formatTick(t), Offset(size.width, ty), palette.onSurfaceVariant, align: _Align.rightMiddle);
    }

    // The crosshair: readers aim at a date, not at a 2px line.
    if (active != null) {
      canvas.drawLine(
        Offset(f.x(active!), f.plot.top),
        Offset(f.x(active!), f.plot.bottom),
        Paint()
          ..color = palette.outline
          ..strokeWidth = 1,
      );
    }

    // Labels under the plot; the one pointed at stands out.
    final focusLabel = active ?? n - 1;
    for (final (i, label) in labels.indexed) {
      if (label == null) continue;
      final pointed = i == focusLabel;
      _text(
        canvas,
        label,
        Offset(f.x(i), size.height - _xBand / 2 + 2),
        pointed ? palette.onSurface : palette.onSurfaceVariant,
        align: _Align.centre,
        bold: pointed,
      );
    }

    if (nums.isEmpty) return;

    if (!single) {
      _paintMany(canvas, f);
      return;
    }

    // One series' average, dashed and behind the data, so it reads as a
    // reference and not as data; its tag goes on top so nothing hides it.
    final s = series.first;
    final own = s.values.whereType<num>().toList();
    final my = band == null ? f.y(own.reduce((a, b) => a + b) / own.length) : null;
    if (my != null) {
      _dashed(
        canvas,
        Offset(f.plot.left, my),
        Offset(f.plot.right, my),
        palette.onSurfaceVariant.withValues(alpha: 0.6),
      );
    }

    switch (hero!) {
      case HeroStyle.bars:
        _paintBars(canvas, f, [s], litOnly: true, values: n <= 7);
      case HeroStyle.area:
        _paintLine(canvas, f, s, wash: true, width: 3);
        _pointed(canvas, f, s, s.color);
      case HeroStyle.band:
        _paintBand(canvas, f, s, band);
    }

    if (my != null) {
      final bars = hero == HeroStyle.bars;
      // Under the line beside bars, where it cannot land on a bar's value.
      _text(
        canvas,
        'avg',
        Offset(f.plot.left + 4, bars ? my + 4 : my),
        palette.onSurfaceVariant,
        align: bars ? _Align.leftTop : _Align.leftMiddle,
        background: palette.surfaceContainerHigh,
      );
    }
  }

  /// Several series on one axis: the bars behind, grouped side by side in
  /// each slot, and the lines over them.
  void _paintMany(Canvas canvas, _Frame f) {
    final bars = series.where((s) => s.mark == ChartMark.bar).toList();
    final lines = series.where((s) => s.mark == ChartMark.line).toList();
    if (bars.isNotEmpty) _paintBars(canvas, f, bars, litOnly: false, values: false);
    for (final s in lines) {
      // A wash under one line reads as "how much"; under several it would
      // just muddy them.
      _paintLine(canvas, f, s, wash: lines.length == 1 && bars.isEmpty, width: 2.5);
    }
    for (final s in lines) {
      _pointed(canvas, f, s, s.color);
    }
  }

  /// [litOnly]: a single metric's bars, faded but for the one pointed at.
  /// Otherwise all are solid until the crosshair picks one out.
  void _paintBars(Canvas canvas, _Frame f, List<HealthSeries> group, {required bool litOnly, required bool values}) {
    final gap = group.length > 1 ? 2.0 : 0.0;
    final groupWidth = math.min(f.slot * 0.62, 44.0 * group.length);
    final width = (groupWidth - gap * (group.length - 1)) / group.length;
    final radius = Radius.circular(math.min(width / 2, 12));
    final focus = _focus;
    final base = f.base;
    for (final (k, s) in group.indexed) {
      for (final (i, v) in s.values.indexed) {
        if (v == null) continue;
        final pointed = i == focus;
        final left = f.x(i) - groupWidth / 2 + k * (width + gap);
        final end = f.y(v);
        final alpha = litOnly ? (pointed ? 1.0 : 0.3) : (active == null || pointed ? 1.0 : 0.4);
        final paint = Paint()..color = s.color.withValues(alpha: alpha);
        final Rect rect;
        if (litOnly) {
          // One metric's capsules, never shorter than their rounded end so a
          // small day still reads as a bar and not a dot.
          rect = Rect.fromLTRB(left, math.min(end, base - width / 2), left + width, base);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
        } else {
          // Several series share the axis, so each bar is its true length:
          // square where it leaves zero, rounded at its end, up or down.
          rect = Rect.fromLTRB(left, math.min(end, base), left + width, math.max(end, base));
          final r = Radius.circular(math.min(radius.x, rect.height));
          canvas.drawRRect(
            v >= 0
                ? RRect.fromRectAndCorners(rect, topLeft: r, topRight: r)
                : RRect.fromRectAndCorners(rect, bottomLeft: r, bottomRight: r),
            paint,
          );
        }
        // A value over each bar while there is room for it.
        if (values) {
          _text(
            canvas,
            formatTick(v),
            Offset(left + width / 2, rect.top - 4),
            pointed ? palette.onSurface : palette.onSurfaceVariant,
            align: _Align.centreBottom,
            bold: pointed,
            background: palette.surface,
          );
        }
      }
    }
  }

  void _paintLine(Canvas canvas, _Frame f, HealthSeries s, {required bool wash, required double width}) {
    final stroke = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = ui.Gradient.linear(Offset(0, f.plot.top), Offset(0, f.plot.bottom), [
        s.color.withValues(alpha: 0.26),
        s.color.withValues(alpha: 0),
      ]);
    for (final run in _runs(f, s)) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 3.5, Paint()..color = s.color);
        continue;
      }
      final line = s.smooth ? _monotone(run) : _straight(run);
      if (wash) {
        final area = Path.from(line)
          ..lineTo(run.last.dx, f.plot.bottom)
          ..lineTo(run.first.dx, f.plot.bottom)
          ..close();
        canvas.drawPath(area, fill);
      }
      canvas.drawPath(line, stroke);
    }
  }

  void _paintBand(Canvas canvas, _Frame f, HealthSeries s, NormalRange? band) {
    final warn = palette.warning.color;
    final color = s.color;
    if (band != null) {
      final rect = Rect.fromLTRB(f.plot.left, f.y(band.hi), f.plot.right, f.y(band.lo));
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
    for (final run in _runs(f, s)) {
      if (run.length > 1) canvas.drawPath(_straight(run), line);
    }

    // Days outside the band are what this chart is for, on the good side
    // as much as the bad; past a month the days inside are left to the line.
    Verdict verdict(num v) => band == null ? Verdict.usual : verdictFor(bandStatus(band, v), better);
    final n = s.values.length;
    final focus = _focus;
    for (final (i, v) in s.values.indexed) {
      if (v == null || i == focus) continue;
      final at = Offset(f.x(i), f.y(v));
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
    final pointed = focus < 0 ? null : s.values[focus];
    _pointed(canvas, f, s, pointed != null && verdict(pointed) == Verdict.worse ? warn : color);
  }

  /// The value pointed at: a ringed dot in a soft halo.
  void _pointed(Canvas canvas, _Frame f, HealthSeries s, Color c) {
    final i = _focus;
    final v = i < 0 ? null : s.values[i];
    if (v == null) return;
    final at = Offset(f.x(i), f.y(v));
    canvas.drawCircle(at, 11, Paint()..color = c.withValues(alpha: 0.18));
    canvas.drawCircle(at, 6.5, Paint()..color = palette.surface);
    canvas.drawCircle(at, 4.5, Paint()..color = c);
  }

  /// The points split at every missing value.
  List<List<Offset>> _runs(_Frame f, HealthSeries s) {
    final runs = <List<Offset>>[];
    var current = <Offset>[];
    for (final (i, v) in s.values.indexed) {
      if (v == null) {
        if (current.isNotEmpty) runs.add(current);
        current = [];
      } else {
        current.add(Offset(f.x(i), f.y(v)));
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
    final aligned = switch (align) {
      _Align.rightMiddle => at - Offset(painter.width, painter.height / 2),
      _Align.centre => at - Offset(painter.width / 2, painter.height / 2),
      _Align.centreBottom => at - Offset(painter.width / 2, painter.height),
      _Align.leftBottom => at - Offset(0, painter.height),
      _Align.leftMiddle => at - Offset(-4, painter.height / 2),
      _Align.leftTop => at + const Offset(4, 0),
    };
    // A label centred on the first or last slot would hang off the edge.
    final offset = Offset(aligned.dx.clamp(0, math.max(0, _width - painter.width)), aligned.dy);
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
      old.series != series ||
      old.style != style ||
      old.labels != labels ||
      old.normal != normal ||
      old.better != better ||
      old.active != active ||
      old.palette != palette;
}

enum _Align { rightMiddle, centre, centreBottom, leftBottom, leftMiddle, leftTop }

Path _straight(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final pt in pts.skip(1)) {
    path.lineTo(pt.dx, pt.dy);
  }
  return path;
}

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

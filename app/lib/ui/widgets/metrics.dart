// Tiles and sparklines — the pieces the Today and Health tabs are built
// from, ported from fitness-dashboard's web/components/metrics.tsx.

import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../theme/palette.dart';
import 'common.dart';

/// A tonal pill tile: an icon disc, a big value and a label. [progress]
/// (0–1) paints a fill behind the content, as the steps tile does. With
/// [onTap] it becomes a button (the detail sheets arrive in phase 5).
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    this.progress,
    this.labelFirst = false,
    this.onTap,
  });

  final Tone tone;
  final IconData icon;
  final String label;
  final String value;
  final double? progress;
  final bool labelFirst;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TypeScale.headlineSmall.copyWith(color: tone.fg, fontWeight: FontWeight.w700),
    );
    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (labelFirst ? TypeScale.labelLarge : TypeScale.labelMedium).copyWith(color: tone.fg),
    );
    return TilePill(
      background: tone.bg,
      progress: progress,
      fill: tone.fill,
      onTap: onTap,
      child: Row(
        children: [
          IconDisc(icon: icon, background: tone.chip, color: tone.icon, size: 44, iconSize: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: labelFirst
                  ? [labelText, const SizedBox(height: 2), valueText]
                  : [valueText, const SizedBox(height: 2), labelText],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill every tile is cut from, so the beer tile cannot drift from
/// the metric tiles beside it.
class TilePill extends StatelessWidget {
  const TilePill({super.key, required this.background, required this.child, this.progress, this.fill, this.onTap});

  final Color background;
  final Widget child;
  final double? progress;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pct = progress?.clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              if (pct != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct,
                    child: ColoredBox(color: fill!),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(height: 68, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The beer counter as a tile (ADR-019), read-only until phase 5 brings the
/// stepper and the Beer sheet: the count in the disc, the litres under the
/// label.
class DrinkTile extends StatelessWidget {
  const DrinkTile({super.key, required this.tone, required this.count, required this.volumeL});

  final Tone tone;

  /// Null until the counter first arrives.
  final int? count;
  final num? volumeL;

  @override
  Widget build(BuildContext context) {
    final sub = count != null && count! > 0 && volumeL != null ? fmtDrinkVolume(count!, volumeL!) : null;
    return TilePill(
      background: tone.bg,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(color: tone.chip, shape: BoxShape.circle),
            child: Text(
              count?.toString() ?? dash,
              style: (count != null && count! > 99 ? TypeScale.titleMedium : TypeScale.headlineSmall).copyWith(
                color: tone.fg,
                fontWeight: FontWeight.w700,
                fontFeatures: TypeScale.tabular,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Beer', maxLines: 1, style: TypeScale.labelLarge.copyWith(color: tone.fg)),
                if (sub != null)
                  Text(sub, maxLines: 1, style: TypeScale.labelSmall.copyWith(color: tone.fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A sparkline with a tinted band behind it (the Health tab's featured
/// card), or with [dense] a bare hairline for a list row.
class MiniChart extends StatelessWidget {
  const MiniChart({super.key, required this.values, required this.color, required this.band, this.dense = false});

  final List<num?> values;
  final Color color;
  final Color band;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: dense ? 60 / 24 : 150 / 58,
      child: CustomPaint(painter: _MiniChartPainter(values, color, band, dense)),
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  _MiniChartPainter(this.values, this.color, this.band, this.dense);

  final List<num?> values;
  final Color color;
  final Color band;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in the web's SVG viewBox units and scaled to fit.
    final (vw, vh) = dense ? (60.0, 24.0) : (150.0, 58.0);
    canvas.scale(size.width / vw, size.height / vh);

    final nums = values.whereType<num>();
    final min = nums.isEmpty ? 0 : nums.reduce((a, b) => a < b ? a : b);
    final max = nums.isEmpty ? 1 : nums.reduce((a, b) => a > b ? a : b);
    final span = (max - min) == 0 ? 1 : max - min;
    final steps = (values.length - 1).clamp(1, 1 << 30);

    final points = <Offset?>[
      for (final (i, v) in values.indexed)
        v == null
            ? null
            : dense
            ? Offset(i / steps * 60, 20 - (v - min) / span * 16)
            : Offset(10 + i / steps * 130, 44 - (v - min) / span * 28),
    ];

    if (!dense) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(4, 8, 142, 42), const Radius.circular(12)),
        Paint()..color = band,
      );
    }

    final line = points.whereType<Offset>().toList();
    if (line.isNotEmpty) {
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (final p in line.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = dense ? 1.75 : 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (!dense) {
      for (final p in line) {
        canvas.drawCircle(p, 3, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_MiniChartPainter old) =>
      old.values != values || old.color != color || old.band != band || old.dense != dense;
}

/// The Health tab's featured card: title, big value, sparkline, weekday
/// row and a chip.
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.title,
    required this.value,
    required this.values,
    required this.dates,
    required this.color,
    required this.band,
    required this.chip,
  });

  final String title;
  final String value;
  final List<num?> values;
  final List<DateTime> dates;
  final Color color;
  final Color band;
  final String chip;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Shape.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: TypeScale.headlineSmall.copyWith(color: p.onSurface)),
          const SizedBox(height: 12),
          MiniChart(values: values, color: color, band: band),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (i, d) in dates.indexed)
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: i == dates.length - 1
                        ? BoxDecoration(color: p.surfaceContainerHighest, shape: BoxShape.circle)
                        : null,
                    child: Text(
                      weekdayNarrow(d),
                      style: TypeScale.labelMedium.copyWith(
                        color: i == dates.length - 1 ? p.onSurface : p.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: p.surfaceContainerHigh, borderRadius: BorderRadius.circular(Shape.sm)),
            child: Text(chip, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// One figure in a row of them: a dotted label, the value, a note.
class StatColumn extends StatelessWidget {
  const StatColumn({super.key, required this.label, required this.value, this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (color != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(label, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TypeScale.headlineSmall.copyWith(color: p.onSurface)),
        if (sub != null) Text(sub!, style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant)),
      ],
    );
  }
}

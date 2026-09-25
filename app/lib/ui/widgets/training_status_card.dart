// Training status, the headline card on the Fitness tab — ported from
// fitness-dashboard's web/components/TrainingStatusCard.tsx.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'metrics.dart';

class TrainingStatusCard extends StatelessWidget {
  const TrainingStatusCard({super.key, required this.data});

  final TrainingStatusOut data;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (:label, :tone) = p.statusTone(data.status);
    final enough = data.status != 'insufficient_data';
    final recovery = data.recovery;

    String signed0(num v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Shape.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Training status', style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: ShapeDecoration(color: tone.bg, shape: const StadiumBorder()),
                child: Text(label, style: TypeScale.labelMedium.copyWith(color: tone.fg)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(data.headline, style: TypeScale.bodyLarge.copyWith(color: p.onSurface)),
          if (enough) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatColumn(
                    label: 'Fitness',
                    value: data.fitness.toStringAsFixed(1),
                    sub: '${data.rampPct >= 0 ? '↑' : '↓'}${data.rampPct.abs().toStringAsFixed(1)}% / 7d',
                    color: p.fitnessColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatColumn(
                    label: 'Fatigue',
                    value: data.fatigue.toStringAsFixed(1),
                    sub: '7-day load',
                    color: p.fatigueColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatColumn(
                    label: 'Form',
                    value: signed0(data.form),
                    sub: '${signed0(data.formPct)}% of fitness',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The performance-management chart. Tapping it opens the history
            // sheet in phase 5.
            LoadChart(series: data.series),
            if (recovery != null) ...[
              const SizedBox(height: 12),
              _RecoveryBar(recovery: recovery, parts: data.recoveryParts),
            ],
          ],
          if (data.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final note in data.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(note, style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant)),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecoveryBar extends StatelessWidget {
  const _RecoveryBar({required this.recovery, required this.parts});

  final int recovery;
  final Map<String, num> parts;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = recovery >= 60
        ? p.success.color
        : recovery >= 40
        ? p.warning.color
        : p.error.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recovery', style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
            ),
            Text('$recovery/100', style: TypeScale.labelMedium.copyWith(color: p.onSurface)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            // expand: without it the Stack hands the fill loose constraints,
            // and an empty DecoratedBox takes them as zero height.
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: p.surfaceContainerHighest),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (recovery / 100).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          children: [
            for (final MapEntry(:key, :value) in parts.entries)
              Text(
                // JavaScript's replace("_", " ") swaps the first underscore only.
                '${key.replaceFirst('_', ' ')} ${(value + 0.5).floor()}',
                style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

/// Daily load as bars, fitness and fatigue as the two averages riding on
/// top — the last 42 days.
class LoadChart extends StatelessWidget {
  const LoadChart({super.key, required this.series});

  final List<DayPointOut> series;

  @override
  Widget build(BuildContext context) {
    final points = series.length > 42 ? series.sublist(series.length - 42) : series;
    if (points.length < 2) return const SizedBox.shrink();
    final p = Palette.of(context);
    return AspectRatio(
      aspectRatio: 320 / 118,
      child: CustomPaint(
        painter: _LoadChartPainter(
          points,
          bar: p.surfaceContainerHighest,
          fitness: p.fitnessColor,
          fatigue: p.fatigueColor,
        ),
      ),
    );
  }
}

class _LoadChartPainter extends CustomPainter {
  _LoadChartPainter(this.points, {required this.bar, required this.fitness, required this.fatigue});

  final List<DayPointOut> points;
  final Color bar;
  final Color fitness;
  final Color fatigue;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 320.0, h = 118.0, pad = 6.0;
    canvas.scale(size.width / w, size.height / h);

    var max = 1.0;
    for (final pt in points) {
      for (final v in [pt.fitness, pt.fatigue, pt.load]) {
        if (v > max) max = v.toDouble();
      }
    }
    double x(int i) => pad + i / (points.length - 1) * (w - pad * 2);
    double y(num v) => h - pad - v / max * (h - pad * 2);
    final barW = ((w - pad * 2) / points.length - 1.6).clamp(2.0, double.infinity);

    final barPaint = Paint()..color = bar;
    for (final (i, pt) in points.indexed) {
      final top = y(pt.load);
      final height = (h - pad - top).clamp(0.0, double.infinity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x(i) - barW / 2, top, barW, height),
          Radius.circular(barW / 2 < 2 ? barW / 2 : 2),
        ),
        barPaint,
      );
    }

    Path line(num Function(DayPointOut) pick) {
      final path = Path()..moveTo(x(0), y(pick(points.first)));
      for (var i = 1; i < points.length; i++) {
        path.lineTo(x(i), y(pick(points[i])));
      }
      return path;
    }

    final area = line((pt) => pt.fitness)
      ..lineTo(x(points.length - 1), h - pad)
      ..lineTo(x(0), h - pad)
      ..close();
    canvas.drawPath(area, Paint()..color = fitness.withValues(alpha: 0.12));

    Paint stroke(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line((pt) => pt.fatigue), stroke(fatigue, 2));
    canvas.drawPath(line((pt) => pt.fitness), stroke(fitness, 2.6));
  }

  @override
  bool shouldRepaint(_LoadChartPainter old) =>
      old.points != points || old.bar != bar || old.fitness != fitness || old.fatigue != fatigue;
}

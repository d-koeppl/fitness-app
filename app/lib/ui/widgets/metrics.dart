// Tiles and sparklines — the pieces the Today and Health tabs are built
// from, ported from fitness-dashboard's web/components/metrics.tsx.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/format.dart';
import '../theme/palette.dart';
import 'common.dart';

/// A tonal pill tile: an icon disc, a big value and a label. [progress]
/// (0–1) paints a fill behind the content, as the steps tile does. With
/// [onTap] it becomes a button that opens the metric's sheet.
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

/// The beer counter as a tile (ADR-019).
///
/// The count takes the disc the other tiles use for their icon, because on
/// this one the number *is* the metric — and it doubles as the way in to
/// typing one: eleven beers is a number you enter, not a number you tap to.
/// Minus and plus sit at the trailing edge; the rest of the tile opens the
/// Beer sheet with the days gone by.
class DrinkTile extends StatefulWidget {
  const DrinkTile({
    super.key,
    required this.tone,
    required this.count,
    required this.volumeL,
    required this.onAdd,
    required this.onUndo,
    required this.onSet,
    required this.onOpenHistory,
  });

  final Tone tone;

  /// Null until the counter first arrives. The controls stay put and go
  /// inert rather than appearing late under a thumb already on its way.
  final int? count;
  final num? volumeL;
  final VoidCallback onAdd;
  final VoidCallback onUndo;
  final ValueChanged<int> onSet;

  /// Unlike the stepper this does not wait for the counter: the sheet reads
  /// its own history.
  final VoidCallback onOpenHistory;

  @override
  State<DrinkTile> createState() => _DrinkTileState();
}

class _DrinkTileState extends State<DrinkTile> {
  final _typed = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    // The field opens empty with the count as its hint, so typing replaces
    // rather than appends.
    _typed.text = '';
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  /// Closing without typing means "leave it alone", as does anything
  /// unparseable: the counter is not something to zero by accident.
  void _commit() {
    final next = int.tryParse(_typed.text);
    setState(() => _editing = false);
    if (next != null && next >= 0 && next != widget.count) widget.onSet(next > 99 ? 99 : next);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final count = widget.count;
    final loaded = count != null;
    final sub = loaded && count > 0 && widget.volumeL != null ? fmtDrinkVolume(count, widget.volumeL!) : null;
    final countStyle = (loaded && count > 99 ? TypeScale.titleMedium : TypeScale.headlineSmall).copyWith(
      color: tone.fg,
      fontWeight: FontWeight.w700,
      fontFeatures: TypeScale.tabular,
    );

    Widget step(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: tone.chip,
        foregroundColor: tone.fg,
        disabledBackgroundColor: tone.chip.withValues(alpha: 0.5),
        disabledForegroundColor: tone.fg.withValues(alpha: 0.4),
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 18),
    );

    final disc = _editing
        ? Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            // Drawn inside the disc, so the field reads as the same round
            // chip in a different state.
            decoration: BoxDecoration(
              color: tone.chip,
              shape: BoxShape.circle,
              border: Border.all(color: tone.fg, width: 2),
            ),
            child: TextField(
              controller: _typed,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              onSubmitted: (_) => _commit(),
              style: countStyle,
              decoration: InputDecoration(
                hintText: '$count',
                hintStyle: countStyle.copyWith(color: tone.fg.withValues(alpha: 0.35)),
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          )
        : Tooltip(
            message: '${count ?? 0} beers. Type a different number',
            child: Material(
              color: tone.chip,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: loaded ? _startEditing : null,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: Text(loaded ? '$count' : dash, style: countStyle)),
                ),
              ),
            ),
          );

    return TilePill(
      background: tone.bg,
      onTap: _editing ? null : widget.onOpenHistory,
      child: Row(
        children: [
          Padding(padding: const EdgeInsets.only(left: 2), child: disc),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // On a phone the disc and steppers leave the label about
                // 40dp, which a raised system font size overruns: shrink
                // the word rather than cut it to "B…".
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Beer', maxLines: 1, style: TypeScale.labelLarge.copyWith(color: tone.fg)),
                ),
                if (sub != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sub,
                      maxLines: 1,
                      style: TypeScale.labelSmall.copyWith(color: tone.fg.withValues(alpha: 0.85)),
                    ),
                  ),
              ],
            ),
          ),
          step(Icons.remove, 'One fewer beer', loaded && count > 0 ? widget.onUndo : null),
          const SizedBox(width: 2),
          step(Icons.add, 'One more beer', loaded ? widget.onAdd : null),
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
    this.onTap,
  });

  final String title;
  final String value;
  final List<num?> values;
  final List<DateTime> dates;
  final Color color;
  final Color band;
  final String chip;

  /// Opens the metric's sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Shape.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
        ),
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TypeScale.headlineSmall.copyWith(color: p.onSurface)),
        if (sub != null) Text(sub!, style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant)),
      ],
    );
  }
}

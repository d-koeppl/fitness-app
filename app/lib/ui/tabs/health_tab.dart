// The eleven key metrics and the range that drives them — ported from
// fitness-dashboard's web/components/tabs/HealthTab.tsx. One metric is
// drawn at chart size over the whole range, in the style its kind of number
// wants (heroStyleFor); the rest sit under it as a list, each with a track
// showing where today falls in the range.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/health_chart.dart';
import '../../domain/key_metrics.dart';
import '../charts/health_chart.dart';
import '../sheets/detail_sheet.dart';
import '../sheets/metric_detail.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

/// The same icon each metric wears on the Today tiles.
const _metricIcon = <MetricKey, IconData>{
  MetricKey.restingHr: Icons.favorite_border,
  MetricKey.hrvMs: Icons.monitor_heart_outlined,
  MetricKey.steps: Icons.directions_walk,
  MetricKey.sleepMinutes: Icons.bedtime_outlined,
  MetricKey.weightKg: Icons.monitor_weight_outlined,
  MetricKey.vo2max: Icons.air,
  MetricKey.readiness: Icons.directions_run,
  MetricKey.recovery: Icons.favorite_border,
  MetricKey.fitness: Icons.directions_run,
  MetricKey.fatigue: Icons.local_fire_department_outlined,
  MetricKey.form: Icons.emoji_events_outlined,
};

/// Everything one card needs, already reduced to numbers and strings.
class MetricCard {
  const MetricCard({
    required this.metric,
    required this.value,
    required this.values,
    required this.dates,
    required this.chip,
    this.normal,
    this.position,
  });

  final MetricDef metric;
  final String value;

  /// The range, oldest first: what the featured chart draws.
  final List<num?> values;
  final List<DateTime> dates;
  final String chip;

  /// The last [baselineDays] days' normal, for a [HeroStyle.band] metric.
  final NormalRange? normal;

  /// Where the current value sits in the range, for the list row.
  final RangePosition? position;

  MetricKey get key => metric.key;
  String get title => metric.title;
  MetricHue get hue => metric.color;
  HeroStyle get style => heroStyleFor(metric.key);
}

/// One card from a metric and the rows it reads (oldest first).
///
/// [range] drives the chart, the row's track and the chip's average; the
/// normal band looks further back, over [baselineDays] of [rows].
MetricCard buildCard<T>({
  required MetricDef metric,
  required List<T> rows,
  required DateTime Function(T row) date,
  required num? Function(T row) pick,
  required int range,
  LatestMeasurementsOut? lastKnown,
}) {
  final newest = rows.isEmpty ? null : rows.last;
  final MeasurementOut? carried = switch (metric.key) {
    MetricKey.weightKg => lastKnown?.weightKg,
    MetricKey.vo2max => lastKnown?.vo2max,
    _ => null,
  };
  final reading = currentReading(newest == null ? null : pick(newest), newest == null ? null : date(newest), carried);
  final current = reading?.value;
  final inRange = rows.length > range ? rows.sublist(rows.length - range) : rows;
  final rangeValues = inRange.map(pick).toList();
  final rangeAvg = average(rangeValues);
  final baseline = rows.length > baselineDays ? rows.sublist(rows.length - baselineDays) : rows;

  final String chip;
  if (metric.key == MetricKey.steps) {
    chip = current != null ? '${jsRound(current / stepGoal * 100)}% of goal' : 'No data yet';
  } else if (reading?.carried ?? false) {
    chip = withMeasuredOn('Last', reading!.date);
  } else if (rangeAvg != null) {
    chip = '$range-day avg ${metric.format(rangeAvg)}';
  } else {
    chip = 'No data yet';
  }

  return MetricCard(
    metric: metric,
    value: current != null ? metric.format(current) : dash,
    // What was measured: a carried-forward value is not drawn as a point.
    values: rangeValues,
    dates: inRange.map(date).toList(),
    chip: chip,
    normal: heroStyleFor(metric.key) == HeroStyle.band ? normalRange(baseline.map(pick)) : null,
    position: rangePosition(rangeValues, current),
  );
}

/// The cards the tab shows, in its order: the six watch metrics, then
/// Fitness, Fatigue and Form, then the two scores.
List<MetricCard> buildCards(DashboardState state, int range) {
  final data = state.data;
  final training = data.training;
  final healthReady = data.healthConnected && state.errors.daily == null && data.daily.isNotEmpty;
  return [
    if (healthReady)
      for (final metric in healthMetrics)
        buildCard<DailyHealthOut>(
          metric: metric,
          rows: data.daily,
          date: (row) => row.date,
          pick: metric.pick,
          range: range,
          lastKnown: data.lastKnown,
        ),
    if (training != null && training.series.isNotEmpty)
      for (final metric in loadMetrics)
        buildCard<DayPointOut>(
          metric: metric,
          rows: training.series,
          date: (row) => parseDay(row.date),
          pick: metric.pick,
          range: range,
        ),
    if (training != null && training.scores.isNotEmpty)
      for (final metric in scoreMetrics)
        buildCard<ScorePointOut>(
          metric: metric,
          rows: training.scores,
          date: (row) => parseDay(row.date),
          pick: metric.pick,
          range: range,
        ),
  ];
}

final _featuredProvider = NotifierProvider<_Featured, MetricKey?>(_Featured.new);

class _Featured extends Notifier<MetricKey?> {
  @override
  MetricKey? build() => null;

  void set(MetricKey key) => state = key;
}

class HealthTab extends ConsumerWidget {
  const HealthTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final range = ref.watch(healthRangeProvider);
    final p = Palette.of(context);
    final data = state.data;
    final cards = buildCards(state, range);
    final featuredKey = ref.watch(_featuredProvider);
    final featured = cards.where((c) => c.key == featuredKey).firstOrNull ?? cards.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Key metrics',
          action: SegmentedPills<int>(
            options: HealthRange.options,
            selected: range,
            label: (r) => '${r}d',
            onSelect: ref.read(healthRangeProvider.notifier).set,
            dense: true,
          ),
        ),
        if (!data.healthConnected && state.lastSynced != null)
          ConnectCard(
            text: 'Connect Google Health to see steps, sleep, and heart rate.',
            consentUrl: () => ref.read(dashboardProvider.notifier).connectUrl('health'),
          ),
        if (data.healthConnected && state.errors.daily != null)
          Notice('Could not load health data: ${state.errors.daily}', tone: NoticeTone.error),
        if (data.healthConnected && state.errors.daily == null && data.daily.isEmpty && state.lastSynced != null)
          const Notice('No health data synced yet — the sync runs hourly.'),
        if (state.errors.training != null)
          Notice('Could not load training status: ${state.errors.training}', tone: NoticeTone.error),
        if (state.errors.training == null && data.training != null && data.training!.series.isEmpty)
          Notice(data.training!.headline),
        if (featured != null) ...[
          _FeaturedCard(featured, range: range, onTap: () => _open(context, featured.key)),
          const SizedBox(height: 12),
          _MetricChips(cards: cards, selected: featured.key, onSelect: ref.read(_featuredProvider.notifier).set),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final (i, card) in cards.where((c) => c.key != featured.key).indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: p.outlineVariant),
                  _MetricRow(card),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricChips extends StatelessWidget {
  const _MetricChips({required this.cards, required this.selected, required this.onSelect});

  final List<MetricCard> cards;
  final MetricKey selected;
  final ValueChanged<MetricKey> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final card in cards) ...[
            Material(
              color: card.key == selected ? p.secondary.container : p.surface,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(card.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    card.title,
                    style: TypeScale.labelMedium.copyWith(
                      color: card.key == selected ? p.secondary.onContainer : p.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

void _open(BuildContext context, MetricKey key) => openSheet(context, MetricDetail(metric: metricByKey[key]!));

/// Icon, name, where today sits in the range, and the current value.
class _MetricRow extends StatelessWidget {
  const _MetricRow(this.card);

  final MetricCard card;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = p.hue(card.hue);
    final band = p.band(card.hue);
    final position = card.position;
    final showTrack = position != null && MediaQuery.sizeOf(context).width >= 380;
    return InkWell(
      onTap: () => _open(context, card.key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            IconDisc(icon: _metricIcon[card.key]!, background: band, color: color, size: 34, iconSize: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.bodyMedium.copyWith(color: p.onSurface),
              ),
            ),
            // Hidden on the narrowest phones, as on the web.
            if (showTrack) ...[
              const SizedBox(width: 8),
              RangeTrack(position: position, color: color, formatTick: card.metric.formatTick),
              const SizedBox(width: 16),
            ],
            // A fixed width while the tracks show, so they line up down the list.
            SizedBox(
              width: showTrack ? 76 : null,
              child: Text(
                card.value,
                textAlign: TextAlign.right,
                style: TypeScale.titleSmall.copyWith(color: p.onSurface, fontFeatures: TypeScale.tabular),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The featured metric: its title, big value and chip, and the chart in
/// the metric's style.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard(this.card, {required this.range, required this.onTap});

  final MetricCard card;
  final int range;

  /// Opens the metric's sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final metric = card.metric;
    final newest = card.values.lastOrNull;
    final normal = card.normal;
    final better = betterFor(metric.key);
    final status = normal != null && newest != null ? bandStatus(normal, newest) : null;

    Widget pill(String text, Color background, Color foreground, {Color? dot}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(text, style: TypeScale.labelMedium.copyWith(color: foreground)),
        ],
      ),
    );

    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Shape.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.title, style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    card.value,
                    style: TypeScale.headlineMedium.copyWith(color: p.onSurface, fontFeatures: TypeScale.tabular),
                  ),
                  pill(card.chip, p.surfaceContainerHigh, p.onSurfaceVariant),
                  if (status != null)
                    verdictFor(status, better) != Verdict.worse
                        ? pill(
                            bandStatusLabel(status, better),
                            p.success.container,
                            p.success.onContainer,
                            dot: p.success.color,
                          )
                        : pill(
                            bandStatusLabel(status, better),
                            p.warning.container,
                            p.warning.onContainer,
                            dot: p.warning.color,
                          ),
                ],
              ),
              const SizedBox(height: 16),
              HealthChart(
                style: card.style,
                series: [HealthSeries(values: card.values, color: p.hue(card.hue))],
                labels: heroLabels(card.dates),
                formatTick: metric.formatTick,
                minStep: metric.minStep,
                domain: metric.domain,
                normal: normal,
                better: better,
                semanticLabel: '${card.title}, last $range days',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

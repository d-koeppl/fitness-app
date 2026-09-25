// The eleven key metrics and the range that drives them — ported from
// fitness-dashboard's web/components/tabs/HealthTab.tsx. One metric is
// drawn at chart size, picked from the chip row; the rest sit under it as a
// list. The detail sheet behind each arrives in phase 5.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import '../widgets/metrics.dart';

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
    required this.key,
    required this.title,
    required this.value,
    required this.values,
    required this.dates,
    required this.hue,
    required this.chip,
  });

  final MetricKey key;
  final String title;
  final String value;
  final List<num?> values;
  final List<DateTime> dates;
  final MetricHue hue;
  final String chip;
}

/// One card from a metric and the rows it reads (oldest first).
///
/// The sparkline is always the last seven rows — the weekday row under it
/// has room for seven — while [range] drives the chip's average.
MetricCard buildCard<T>({
  required MetricDef metric,
  required List<T> rows,
  required DateTime Function(T row) date,
  required num? Function(T row) pick,
  required int range,
  LatestMeasurementsOut? lastKnown,
}) {
  final week = rows.length > 7 ? rows.sublist(rows.length - 7) : rows;
  final newest = rows.isEmpty ? null : rows.last;
  final MeasurementOut? carried = switch (metric.key) {
    MetricKey.weightKg => lastKnown?.weightKg,
    MetricKey.vo2max => lastKnown?.vo2max,
    _ => null,
  };
  final reading = currentReading(newest == null ? null : pick(newest), newest == null ? null : date(newest), carried);
  final current = reading?.value;
  final inRange = rows.length > range ? rows.sublist(rows.length - range) : rows;
  final rangeAvg = average(inRange.map(pick));

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
    key: metric.key,
    title: metric.title,
    value: current != null ? metric.format(current) : dash,
    // What was measured: a carried-forward value is not drawn as a point.
    values: week.map(pick).toList(),
    dates: week.map(date).toList(),
    hue: metric.color,
    chip: chip,
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
          MetricChartCard(
            title: featured.title,
            value: featured.value,
            values: featured.values,
            dates: featured.dates,
            color: p.hue(featured.hue),
            band: p.band(featured.hue),
            chip: featured.chip,
          ),
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

/// Icon, name, a hairline trend and the current value.
class _MetricRow extends StatelessWidget {
  const _MetricRow(this.card);

  final MetricCard card;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = p.hue(card.hue);
    final band = p.band(card.hue);
    return Padding(
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
          if (MediaQuery.sizeOf(context).width >= 380) ...[
            SizedBox(
              width: 56,
              child: MiniChart(values: card.values, color: color, band: band, dense: true),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            card.value,
            style: TypeScale.titleSmall.copyWith(color: p.onSurface, fontFeatures: TypeScale.tabular),
          ),
        ],
      ),
    );
  }
}

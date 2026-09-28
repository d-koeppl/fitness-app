// The full-screen view behind a tapped key metric: the same number, with a
// scale beside it and a choice of how far back to look. The port of
// fitness-dashboard's web/components/MetricDetail.tsx.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/health_chart.dart';
import '../../domain/key_metrics.dart';
import '../../domain/metric_about.dart';
import '../../domain/series.dart';
import '../widgets/common.dart';
import 'detail_sheet.dart';

class MetricDetail extends ConsumerStatefulWidget {
  const MetricDetail({super.key, required this.metric});

  final MetricDef metric;

  @override
  ConsumerState<MetricDetail> createState() => _MetricDetailState();
}

class _MetricDetailState extends ConsumerState<MetricDetail> {
  var _period = Period.week;
  int? _active;

  // Read the clock once, when the sheet opens: the window does not need to
  // slide under the reader mid-session.
  final _today = startOfDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    // Only the health metrics need a year fetched on demand; the scores and
    // the load averages ride along on the training status already held.
    if (widget.metric is HealthMetricDef) ref.read(healthHistoryProvider.notifier).ensureFresh();
  }

  /// The metric reduced to one number per day, from whichever source holds
  /// it, plus what is still loading and what failed.
  ({List<SeriesPoint> points, bool loading, String? error}) _source() {
    switch (widget.metric) {
      case HealthMetricDef(:final pick):
        final history = ref.watch(healthHistoryProvider);
        return (
          points: [for (final row in history.value ?? const []) (date: row.date, value: pick(row))],
          loading: history.isLoading,
          error: history.hasError ? describeError(history.error!) : null,
        );
      case ScoreMetricDef(:final pick):
        final state = ref.watch(dashboardProvider);
        return (
          points: [for (final p in state.data.training?.scores ?? const []) (date: parseDay(p.date), value: pick(p))],
          loading: state.loading && state.data.training == null,
          error: state.errors.training,
        );
      case LoadMetricDef(:final pick):
        final state = ref.watch(dashboardProvider);
        return (
          points: [for (final p in state.data.training?.series ?? const []) (date: parseDay(p.date), value: pick(p))],
          loading: state.loading && state.data.training == null,
          error: state.errors.training,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final metric = widget.metric;
    final (:points, :loading, :error) = _source();
    final spec = periodSpec(_period);
    final buckets = bucketSeries(points, _period, _today);
    // The daily band says nothing about weekly or monthly averages, which
    // swing far less than days do.
    final since = addDays(_today, -(baselineDays - 1));
    final normal = heroStyleFor(metric.key) == HeroStyle.band && spec.aggregate == Aggregate.daily
        ? normalRange([
            for (final point in points)
              if (!point.date.isBefore(since)) point.value,
          ])
        : null;

    return DetailSheet(
      title: metric.title,
      period: _period,
      onPeriodChange: (next) => setState(() {
        _period = next;
        _active = null;
      }),
      children: [
        if (error != null)
          Notice('Could not load history: $error', tone: NoticeTone.error)
        else
          ChartPanel(
            metric: metric,
            buckets: buckets,
            period: _period,
            today: _today,
            active: _active,
            onActiveChange: (i) => setState(() => _active = i),
            normal: normal,
            dim: loading && points.isEmpty,
          ),
        if (error == null && !loading && seriesAverage(buckets) == null)
          Notice('No ${metric.title.toLowerCase()} recorded in this period.'),
        AboutPanel(about: metricAbout(metric.key)),
        HistoryList(
          heading: spec.long,
          rows: [
            for (final bucket in buckets.reversed)
              HistoryRow(
                label: bucketLabel(bucket, spec.aggregate, _today),
                value: HistoryValue(bucket.value == null ? null : metric.format(bucket.value!)),
              ),
          ],
        ),
      ],
    );
  }
}

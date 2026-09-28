// The full-screen view behind the training-status card: the same load,
// fitness and fatigue, with a scale on them and a choice of how far back.
// The port of fitness-dashboard's web/components/TrainingDetail.tsx.
//
// All three are in the same unit (Active Zone Minutes and the two averages
// of it), which is why they can honestly share one y-axis.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../../domain/metric_about.dart';
import '../../domain/series.dart';
import '../charts/health_chart.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'detail_sheet.dart';

String _oneDecimal(num v) => v.toStringAsFixed(1);

class TrainingDetail extends ConsumerStatefulWidget {
  const TrainingDetail({super.key});

  @override
  ConsumerState<TrainingDetail> createState() => _TrainingDetailState();
}

class _TrainingDetailState extends ConsumerState<TrainingDetail> {
  var _period = Period.month;
  int? _active;
  final _today = startOfDay(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final data = ref.watch(dashboardProvider.select((s) => s.data.training));
    if (data == null) {
      return DetailSheet(title: 'Training load', children: const [Notice('No training status loaded.')]);
    }

    final spec = periodSpec(_period);
    List<Bucket> bucketsOf(num Function(DayPointOut point) pick) => bucketSeries(
      [for (final point in data.series) (date: parseDay(point.date), value: pick(point))],
      _period,
      _today,
    );
    final load = bucketsOf((point) => point.load);
    final fitness = bucketsOf((point) => point.fitness);
    final fatigue = bucketsOf((point) => point.fatigue);

    // Load is the daily impulse; fitness and fatigue are the two exponential
    // averages of it. The order is the legend's, the readout's and the
    // drawing order.
    final lines = [
      (label: 'Fitness', color: p.fitnessColor, buckets: fitness, headline: data.fitness),
      (label: 'Fatigue', color: p.fatigueColor, buckets: fatigue, headline: data.fatigue),
    ];
    final (label: statusLabel, :tone) = p.statusTone(data.status);
    final selected = _active == null ? null : load[_active!];
    // With nothing selected the two lines show their current headline
    // values, so load shows the average over the same window rather than a
    // stale last bar — the three numbers describe the same stretch of time.
    final loadReadout = _active != null ? selected?.value : seriesAverage(load);

    Widget legend(String label, Widget swatch) => Row(
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(label, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
      ],
    );
    final readoutStyle = TypeScale.headlineSmall.copyWith(color: p.onSurface);

    return DetailSheet(
      title: 'Training load',
      period: _period,
      onPeriodChange: (next) => setState(() {
        _period = next;
        _active = null;
      }),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          aggregateCaption(spec.aggregate),
                          style: TypeScale.labelLarge.copyWith(color: p.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selected != null ? bucketLabel(selected, spec.aggregate, _today) : windowLabel(load),
                          style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: ShapeDecoration(color: tone.bg, shape: const StadiumBorder()),
                    child: Text(statusLabel, style: TypeScale.labelMedium.copyWith(color: tone.fg)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Every series at the crosshair's date, so the pointer never has
              // to land on a particular line to get a number.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          legend(
                            line.label,
                            Container(
                              width: 12,
                              height: 2,
                              decoration: BoxDecoration(color: line.color, borderRadius: BorderRadius.circular(1)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _active != null
                                ? (line.buckets[_active!].value == null
                                      ? dash
                                      : _oneDecimal(line.buckets[_active!].value!))
                                : _oneDecimal(line.headline),
                            style: readoutStyle,
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        legend(
                          'Load',
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: p.loadColor, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(loadReadout == null ? dash : _oneDecimal(loadReadout), style: readoutStyle),
                        Text(
                          _active != null ? 'AZM' : 'AZM / day avg',
                          style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              HealthChart(
                series: [
                  HealthSeries(values: [for (final b in load) b.value], color: p.loadColor, mark: ChartMark.bar),
                  for (final line in lines)
                    HealthSeries(values: [for (final b in line.buckets) b.value], color: line.color),
                ],
                labels: tickLabels(load, _period),
                formatTick: (v) => '${jsRound(v)}',
                minStep: 1,
                active: _active,
                onActiveChange: (i) => setState(() => _active = i),
                semanticLabel:
                    'Training load, fitness and fatigue, ${aggregateCaption(spec.aggregate).toLowerCase()} '
                    'for ${spec.long.toLowerCase()}. Values are listed below the chart.',
              ),
              const SizedBox(height: 8),
              Text(data.headline, style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
            ],
          ),
        ),
        if (data.notes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final note in data.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(note, style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant)),
                ),
            ],
          ),
        const AboutPanel(about: trainingLoadAbout),
        HistoryList(
          heading: spec.long,
          header: Row(
            children: [
              for (final label in ['Fitness', 'Fatigue', 'Load'])
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: SizedBox(
                    width: 44,
                    child: Text(
                      label,
                      textAlign: TextAlign.right,
                      style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
          rows: [
            for (var i = load.length - 1; i >= 0; i--)
              HistoryRow(
                label: bucketLabel(load[i], spec.aggregate, _today),
                value: Row(
                  children: [
                    for (final (column, bucket) in [fitness[i], fatigue[i], load[i]].indexed)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: SizedBox(
                          width: 44,
                          child: Text(
                            bucket.value == null ? dash : _oneDecimal(bucket.value!),
                            textAlign: TextAlign.right,
                            style: TypeScale.bodyMedium.copyWith(
                              fontFeatures: TypeScale.tabular,
                              color: bucket.value == null
                                  ? p.outline
                                  : column == 2
                                  ? p.onSurfaceVariant
                                  : lines[column].color,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

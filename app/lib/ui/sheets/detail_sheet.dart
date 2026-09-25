// The frame every detail sheet wears: the full-screen page, the back
// button, the period selector, the history list and the "What this is"
// panel — the port of fitness-dashboard's web/components/DetailSheet.tsx and
// ChartPanel.tsx. Only what sits between them differs per sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../../domain/metric_about.dart';
import '../../domain/series.dart';
import '../charts/metric_chart.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

/// Open a sheet over the whole shell. The route lives on the app's
/// navigator, above the signed-in ProviderScope, so the sheet is handed that
/// scope's container to read the same dashboard the shell does.
Future<void> openSheet(BuildContext context, Widget sheet) {
  final container = ProviderScope.containerOf(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => UncontrolledProviderScope(container: container, child: sheet),
    ),
  );
}

class DetailSheet extends StatelessWidget {
  const DetailSheet({super.key, required this.title, this.period, this.onPeriodChange, required this.children});

  final String title;

  /// Leave both out and the sheet has no period selector: a single session
  /// is one event, and a control offering "the last 12 months" of it would
  /// have nothing to do.
  final Period? period;
  final ValueChanged<Period>? onPeriodChange;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.surfaceContainer,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      style: IconButton.styleFrom(
                        backgroundColor: p.surfaceContainerHighest,
                        foregroundColor: p.onSurface,
                      ),
                      icon: const Icon(Icons.arrow_back, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.titleLarge.copyWith(color: p.onSurface),
                      ),
                    ),
                  ],
                ),
                // The range control sits above everything it scopes.
                if (period != null && onPeriodChange != null) ...[
                  const SizedBox(height: 16),
                  SegmentedPills<Period>(
                    options: Period.values,
                    selected: period!,
                    label: (option) => periodSpec(option).short,
                    onSelect: onPeriodChange!,
                  ),
                ],
                for (final child in children) ...[const SizedBox(height: 16), child],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryRow {
  const HistoryRow({required this.label, required this.value});

  final String label;
  final Widget value;
}

/// The values in full under the chart, so nothing is reachable only by
/// pointing at it. Used for a bucketed series in the chart sheets and for a
/// session's recorded fields in the exercise sheet — same shape, same list.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.heading, this.header, required this.rows});

  final String heading;

  /// Names the value columns, for a list carrying more than one number.
  final Widget? header;
  final List<HistoryRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(heading, style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
              ),
              ?header,
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(Shape.lg),
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const SizedBox(height: 1),
                Container(
                  color: p.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 12),
                      row.value,
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A history row's value: the number, or a dash in the outline colour.
class HistoryValue extends StatelessWidget {
  const HistoryValue(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Text(
      text ?? dash,
      style: TypeScale.titleMedium.copyWith(
        color: text == null ? p.outline : p.onSurface,
        fontFeatures: TypeScale.tabular,
      ),
    );
  }
}

/// "What this is", under the chart: what the metric measures, how to read
/// a value, and what produced it. Collapsed to one row, so it never pushes
/// the history down the page.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key, required this.about});

  final MetricAbout about;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget section(String label, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TypeScale.labelMedium.copyWith(color: p.onSurface)),
          const SizedBox(height: 2),
          Text(text, style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
        ],
      ),
    );

    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Shape.lg)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // No divider lines above and below the tile when it opens.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text('What this is', style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
          iconColor: p.onSurfaceVariant,
          collapsedIconColor: p.onSurfaceVariant,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section('What it shows', about.what),
            section('How to read it', about.read),
            section('Where it comes from', about.source),
          ],
        ),
      ),
    );
  }
}

/// What each period's numbers actually are — an average of weeks and an
/// average of days are not the same claim.
String aggregateCaption(Aggregate aggregate) => switch (aggregate) {
  Aggregate.daily => 'Daily values',
  Aggregate.weekly => 'Weekly averages',
  Aggregate.monthly => 'Monthly averages',
};

/// The card at the top of a one-series sheet: a headline number, what it is
/// a number *of*, the chart, and the newest value in full. Shared so the
/// sheets cannot drift apart on what the big number means — the
/// crosshair's bucket when one is selected, the period's average when not.
class ChartPanel extends StatelessWidget {
  const ChartPanel({
    super.key,
    required this.metric,
    required this.buckets,
    required this.period,
    required this.today,
    required this.active,
    required this.onActiveChange,
    this.dim = false,
  });

  final ChartMetric metric;
  final List<Bucket> buckets;
  final Period period;
  final DateTime today;
  final int? active;
  final ValueChanged<int?> onActiveChange;

  /// Fade the plot while the first load is still in flight, rather than
  /// swapping in a skeleton and jumping the layout.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final spec = periodSpec(period);
    final average = seriesAverage(buckets);
    final newest = latestBucket(buckets);
    final selected = active == null ? null : buckets[active!];

    final headline = selected != null
        ? (selected.value == null ? 'No data' : metric.format(selected.value!))
        : (average == null ? dash : metric.format(average));
    final caption = selected != null
        ? bucketLabel(selected, spec.aggregate, today)
        : (average != null ? 'Average · ${windowLabel(buckets)}' : windowLabel(buckets));

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(aggregateCaption(spec.aggregate), style: TypeScale.labelLarge.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(headline, style: TypeScale.headlineMedium.copyWith(color: p.onSurface)),
          const SizedBox(height: 2),
          Text(caption, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: dim ? 0.4 : 1,
            duration: const Duration(milliseconds: 150),
            child: MetricChart(
              series: [ChartSeries(key: metric.title, color: p.hue(metric.color), mark: metric.mark, buckets: buckets)],
              labels: tickLabels(buckets, period),
              formatTick: metric.formatTick,
              minStep: metric.minStep,
              domain: metric.domain,
              active: active,
              onActiveChange: onActiveChange,
              semanticLabel:
                  '${metric.title}, ${aggregateCaption(spec.aggregate).toLowerCase()} for '
                  '${spec.long.toLowerCase()}. Values are listed below the chart.',
            ),
          ),
          if (newest != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Latest · ${bucketLabel(newest, spec.aggregate, today)}',
                    style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
                  ),
                ),
                Text(metric.format(newest.value!), style: TypeScale.labelMedium.copyWith(color: p.onSurface)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

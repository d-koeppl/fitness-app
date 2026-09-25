// The six tiles worth a glance every day, the beer stepper, New report and
// the AI report — ported from fitness-dashboard's
// web/components/tabs/TodayTab.tsx. A tile opens its metric's sheet.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../sheets/detail_sheet.dart';
import '../sheets/drink_detail.dart';
import '../sheets/metric_detail.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import '../widgets/metrics.dart';
import '../widgets/report_text.dart';

class TodayTab extends ConsumerWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final data = state.data;
    final p = Palette.of(context);
    final newReport = ref.watch(newReportProvider);
    final drinkError = ref.watch(drinkStepperProvider) ?? state.errors.drinks;
    final stepper = ref.read(drinkStepperProvider.notifier);
    void open(MetricKey key) => openSheet(context, MetricDetail(metric: metricByKey[key]!));
    final latest = data.latest;
    final previous = data.previous;

    final sleepAvg = average(data.daily.map((d) => d.sleepMinutes));
    final weightAvg = average(data.daily.map((d) => d.weightKg));
    // Weight is not recorded every day: fall back to the last reading and
    // let the subtitle carry its date (ADR-018).
    final weight = currentReading(latest?.weightKg, latest?.date, data.lastKnown?.weightKg);

    final String weightLabel;
    if (weight == null) {
      weightLabel = 'Weight';
    } else if (weight.carried) {
      weightLabel = withMeasuredOn('Weight', weight.date);
    } else if (weightAvg != null) {
      weightLabel =
          'Weight · ${weight.value < weightAvg ? '↓' : '↑'}${(weight.value - weightAvg).abs().toStringAsFixed(1)} avg';
    } else {
      weightLabel = 'Weight';
    }

    final tiles = <Widget>[
      MetricTile(
        tone: p.slate,
        icon: Icons.favorite_border,
        value: latest?.restingHr != null ? '${jsRound(latest!.restingHr!)} bpm' : dash,
        label: withDelta('Resting HR', latest?.restingHr, previous?.restingHr),
        onTap: () => open(MetricKey.restingHr),
      ),
      MetricTile(
        tone: p.slate,
        icon: Icons.monitor_heart_outlined,
        value: latest?.hrvMs != null ? '${jsRound(latest!.hrvMs!)} ms' : dash,
        label: withDelta('Variability', latest?.hrvMs, previous?.hrvMs),
        onTap: () => open(MetricKey.hrvMs),
      ),
      MetricTile(
        tone: p.sleep,
        icon: Icons.bedtime_outlined,
        value: fmtSleep(latest?.sleepMinutes),
        label: sleepAvg != null ? 'Sleep · avg ${fmtSleepCompact(sleepAvg)}' : 'Sleep',
        onTap: () => open(MetricKey.sleepMinutes),
      ),
      MetricTile(
        tone: p.weight,
        icon: Icons.monitor_weight_outlined,
        value: weight != null ? '${weight.value.toStringAsFixed(1)} kg' : dash,
        label: weightLabel,
        onTap: () => open(MetricKey.weightKg),
      ),
      MetricTile(
        tone: p.mint,
        icon: Icons.directions_walk,
        labelFirst: true,
        label: 'Steps',
        value: latest?.steps != null ? fmtInt(latest!.steps!) : dash,
        progress: latest?.steps != null ? latest!.steps! / stepGoal : 0,
        onTap: () => open(MetricKey.steps),
      ),
      DrinkTile(
        tone: p.flame,
        count: data.drinks?.count,
        volumeL: data.drinks?.volumeL,
        onAdd: () => stepper.change(1),
        onUndo: () => stepper.change(-1),
        onSet: stepper.set,
        onOpenHistory: () => openSheet(context, const DrinkDetail()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Two columns on a phone, three from the web's `lg` width up.
            final columns = constraints.maxWidth >= 700 ? 3 : 2;
            const gap = 10.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
            );
          },
        ),
        if (drinkError != null) ...[
          const SizedBox(height: 8),
          Text(
            drinkError,
            textAlign: TextAlign.center,
            style: TypeScale.labelSmall.copyWith(color: p.error.color),
          ),
        ],
        if (data.missingMatch != null) ...[const SizedBox(height: 16), _MissingMatchNotice(data.missingMatch!)],
        const SizedBox(height: 16),
        // One button (ADR-027): it syncs Google, then reports.
        SizedBox(
          height: 48,
          child: FilledButton.tonalIcon(
            onPressed: newReport.phase == null ? ref.read(newReportProvider.notifier).run : null,
            icon: newReport.phase == null
                ? const Icon(Icons.add, size: 20)
                : const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            label: Text(switch (newReport.phase) {
              ReportPhase.syncing => 'Syncing…',
              ReportPhase.analyzing => 'Analyzing…',
              null => 'New report',
            }),
          ),
        ),
        const SizedBox(height: 16),
        _ReportCard(
          report: data.report,
          error: state.errors.report,
          generateError: newReport.error,
          loaded: state.reportLoaded,
        ),
        if (!data.healthConnected && state.lastSynced != null) ...[
          const SizedBox(height: 16),
          ConnectCard(
            text: 'Connect Google Health to see steps, sleep, and heart rate.',
            consentUrl: () => ref.read(dashboardProvider.notifier).connectUrl('health'),
          ),
        ],
      ],
    );
  }
}

class _MissingMatchNotice extends StatelessWidget {
  const _MissingMatchNotice(this.missing);

  final MissingMatchOut missing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = TypeScale.bodyMedium.copyWith(color: p.error.onContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: p.error.container, borderRadius: BorderRadius.circular(Shape.lg)),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(
              text: "No ÖFB data for yesterday's game",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text:
                  ' (${missing.title}, ${fmtTime(missing.kickoff)}). The scrape failed, the report isn\'t online yet, '
                  "you weren't in the squad, or the game was called off. The scrape tries again for the next two nights.",
            ),
          ],
        ),
      ),
    );
  }
}

/// The AI report as the big editorial card, in three states: still asking,
/// asked and there is none, and the report.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.error, required this.generateError, required this.loaded});

  final AiReportOut? report;
  final String? error;

  /// New report failed. Said on its own line, above the report it did not
  /// replace, rather than hiding that report behind the error.
  final String? generateError;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final report = this.report;
    final readiness = report?.readiness;
    final parts = report == null ? null : splitReport(report);
    final readyTone = p.readyTone(readiness);

    Widget skeleton(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: p.surfaceContainerHigh, borderRadius: BorderRadius.circular(Shape.sm)),
      ),
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: p.primary.color),
              const SizedBox(width: 8),
              Text(
                report != null ? fmtTime(report.createdAt) : dash,
                style: TypeScale.labelLarge.copyWith(color: p.onSurfaceVariant),
              ),
              const Spacer(),
              if (readiness != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: ShapeDecoration(color: readyTone.bg, shape: const StadiumBorder()),
                    child: Text(
                      // CSS `capitalize`: every word's first letter.
                      '$readiness readiness'
                          .split(' ')
                          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                          .join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.labelMedium.copyWith(color: readyTone.fg),
                    ),
                  ),
                ),
            ],
          ),
          if (generateError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Could not generate a new report: $generateError',
              style: TypeScale.bodyMedium.copyWith(color: p.error.color),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text('Could not load the latest report: $error', style: TypeScale.bodyLarge.copyWith(color: p.error.color)),
          ] else if (report == null && !loaded) ...[
            const SizedBox(height: 8),
            skeleton(0.8, 28),
            skeleton(0.6, 28),
            skeleton(1, 16),
            skeleton(0.92, 16),
          ] else if (report == null) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'No report yet — tap '),
                  TextSpan(
                    text: 'New report',
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.onSurface),
                  ),
                  const TextSpan(text: ', or wait for the morning run.'),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(parts!.headline, style: TypeScale.headlineMedium.copyWith(color: p.onSurface)),
            const SizedBox(height: 12),
            ReportText(parts.body),
            if (report.recommendations.isNotEmpty) ...[
              const SizedBox(height: 20),
              for (final rec in report.recommendations)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: p.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Shape.lg),
                  ),
                  child: Text(rec, style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
                ),
            ],
            if (report.flags.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: p.warning.container, borderRadius: BorderRadius.circular(Shape.lg)),
                child: Text(
                  report.flags.join(' · '),
                  style: TypeScale.bodySmall.copyWith(color: p.warning.onContainer),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              '${fmtDateTime(report.createdAt)} · ${report.trigger}',
              style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

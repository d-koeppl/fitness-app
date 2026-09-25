// The full-screen view behind one session: everything known about it, and
// what it contributed to the day. The port of fitness-dashboard's
// web/components/ExerciseDetail.tsx.
//
// No period selector — a session is one event, not a series. The chart it
// does carry is inside the session: the heart rate the watch recorded
// (ADR-020). A session the watch never recorded (a match, a training block)
// gets one section the others do not: the estimate explained, and the
// control that marks it as not done.
//
// "Ask the coach about this session" pins it to the coach chat and opens
// the tab (ADR-021): the coach is sent this session in full — every metric
// and the whole trace, not the summary row the rolling list carries.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/coach.dart';
import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/heart_rate.dart';
import '../../domain/metric_about.dart';
import '../../domain/series.dart';
import '../charts/heart_rate_chart.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import '../widgets/metrics.dart';
import 'detail_sheet.dart';

String _oneDecimal(num v) => v.toStringAsFixed(1);

class ExerciseDetail extends ConsumerStatefulWidget {
  const ExerciseDetail({super.key, required this.session});

  /// The session as the list held it. The sheet follows the dashboard's
  /// copy once there is one, so a skip shows here after the re-read.
  final ExerciseSessionOut session;

  @override
  ConsumerState<ExerciseDetail> createState() => _ExerciseDetailState();
}

class _ExerciseDetailState extends ConsumerState<ExerciseDetail> {
  bool _skipPending = false;
  String? _skipError;

  // Read once, when the sheet opens, like the chart sheets.
  final _today = startOfDay(DateTime.now());

  Future<void> _toggleSkip(ExerciseSessionOut session) async {
    if (_skipPending) return;
    setState(() {
      _skipPending = true;
      _skipError = null;
    });
    try {
      // Resolves once the training status has been re-read, so the button
      // stays busy until the number it changed has actually moved.
      await ref.read(dashboardProvider.notifier).setSkipped(session, !session.skipped);
    } catch (error) {
      if (mounted) setState(() => _skipError = describeError(error));
    } finally {
      if (mounted) setState(() => _skipPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final state = ref.watch(dashboardProvider);
    final session = state.data.exercises.where((s) => s.id == widget.session.id).firstOrNull ?? widget.session;
    final tracked = session.source_ == 'tracked';
    final title = sessionTitle(session);
    final start = session.startTs;
    final when = start != null
        ? '${fmtDate(start)} · ${fmtTime(start)}${session.endTs != null ? '–${fmtTime(session.endTs)}' : ''}'
        : fmtDate(session.date);

    // Measured for a tracked session, estimated for a scheduled one — one
    // helper decides which, so the number here and on the list row agree.
    final (:azm, :estimated) = sessionLoad(session);
    // The whole day's load in the same unit, off the training series the
    // Fitness chart plots. Null for today (the series stops at yesterday
    // while today fills up) and for a day outside the window.
    final dayLoad = state.data.training?.series.where((pt) => parseDay(pt.date) == session.date).firstOrNull?.load;
    // Only worth showing when the day held more than this one session.
    final share = azm != null && azm > 0 && dayLoad != null && dayLoad > azm + 0.05
        ? jsRound(azm / dayLoad * 100)
        : null;

    final recorded = [for (final e in session.metrics.entries) fmtSessionMetric(e.key, e.value)]
      ..sort((a, b) => a.label.compareTo(b.label));

    return DetailSheet(
      title: title,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Session', style: TypeScale.labelLarge.copyWith(color: p.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(fmtDuration(session.durationMinutes), style: TypeScale.headlineMedium.copyWith(color: p.onSurface)),
              const SizedBox(height: 2),
              Text(when, style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "AZM", not "Active Zone Minutes": three columns on a
                  // phone, and a label that wraps drops its value below the
                  // two beside it. The panel below spells it out.
                  Expanded(
                    child: StatColumn(
                      label: 'AZM',
                      value: azm == null ? dash : '${estimated ? '≈' : ''}${_oneDecimal(azm)}',
                      sub: estimated
                          ? (session.skipped ? 'not counted' : 'estimated')
                          : share == null
                          ? "the day's load unit"
                          : '$share% of the day',
                      color: p.fatigueColor,
                    ),
                  ),
                  Expanded(
                    child: StatColumn(
                      label: 'Avg heart rate',
                      value: session.averageHeartRate == null ? dash : '${jsRound(session.averageHeartRate!)}',
                      sub: 'bpm',
                    ),
                  ),
                  Expanded(
                    child: StatColumn(
                      label: "Day's load",
                      value: dayLoad == null ? dash : _oneDecimal(dayLoad),
                      sub: dayLoad != null
                          ? 'AZM total'
                          : session.date == _today
                          ? 'counted tomorrow'
                          : 'out of range',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Straight under the numbers: it is what you want the moment one of
        // them looks wrong. Idempotent — a session already pinned is not
        // toggled off from a screen that gives no sign it was ever on.
        Builder(
          builder: (context) {
            final pinned = ref.watch(coachProvider.select((s) => s.attached.contains(session.id)));
            return SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(coachProvider.notifier).pinFromSession(session.id);
                  Navigator.of(context).maybePop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: pinned ? p.secondary.container : p.primary.container,
                  foregroundColor: pinned ? p.secondary.onContainer : p.primary.onContainer,
                ),
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: Text(pinned ? 'Already attached — open the coach' : 'Ask the coach about this session'),
              ),
            );
          },
        ),
        // Only a tracked session has a trace: a match the watch never
        // recorded has no readings to ask for.
        if (tracked) _HeartRateSection(sessionId: session.id),
        if (!tracked && session.refId != null)
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  session.skipped ? 'Skipped' : 'Not tracked',
                  style: TypeScale.labelLarge.copyWith(color: p.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  session.skipped
                      ? 'This one is not counted towards your training status. Put it back if it went ahead after all.'
                      : 'Nothing the watch recorded starts anywhere near this one, so the load above is estimated from '
                            '${session.source_ == 'match' ? 'the minutes you played' : 'a 90-minute session'} at your '
                            'recent rate. Other sessions that day count on their own. If it did not happen — ill, or no '
                            'time — mark it skipped and it stops counting.',
                  style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: FilledButton.tonal(
                    onPressed: _skipPending ? null : () => _toggleSkip(session),
                    child: Text(
                      _skipPending
                          ? 'Saving…'
                          : session.skipped
                          ? 'Count it again'
                          : 'Mark as skipped',
                    ),
                  ),
                ),
                if (_skipError != null) ...[
                  const SizedBox(height: 8),
                  Text(_skipError!, style: TypeScale.labelMedium.copyWith(color: p.error.color)),
                ],
              ],
            ),
          ),
        // Whatever else the watch recorded, labelled from the field names
        // themselves rather than from a list kept in step with the API.
        if (recorded.isNotEmpty)
          HistoryList(
            heading: 'Also recorded',
            rows: [for (final m in recorded) HistoryRow(label: m.label, value: HistoryValue(m.value))],
          ),
        const AboutPanel(about: exerciseAbout),
        // The untranslated activity name, so a type without a nice label is
        // still identifiable rather than just "Workout".
        if (session.exerciseType != null)
          Text(
            'Recorded by Google Health as ${session.exerciseType}.',
            style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _HeartRateSection extends ConsumerWidget {
  const _HeartRateSection({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final trace = ref.watch(sessionHeartRateProvider(sessionId));
    final value = trace.value;
    final empty = value == null ? null : emptyTraceReason(value);
    final muted = TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant);

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Heart rate', style: TypeScale.titleSmall.copyWith(color: p.onSurfaceVariant)),
              ),
              if (value?.maxBpm != null)
                Text(
                  '${value!.minBpm}–${value.maxBpm} bpm',
                  style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant, fontFeatures: TypeScale.tabular),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (trace.isLoading)
            Text('Loading…', style: muted)
          else if (trace.hasError)
            Text(describeError(trace.error!), style: TypeScale.labelMedium.copyWith(color: p.error.color))
          else if (empty != null)
            Text(empty, style: muted)
          else if (value != null) ...[
            HeartRateChart(trace: value),
            // Said out loud because it is the one number on this chart nobody
            // measured: the API reports minutes per zone but not the bpm they
            // start at, so the bands are worked out from a resting and a max
            // heart rate.
            Text(
              [
                value.zones.isEmpty
                    ? 'Zones need a maximum heart rate — set HEALTH_MAX_HR_BPM (or HEALTH_BIRTH_YEAR) and the trace is '
                          'coloured by zone.'
                    : 'Zone boundaries from a resting ${value.restingHr} and a maximum of ${value.maxHr} bpm. Times in '
                          'each zone ${value.zoneSource == 'google' ? 'as Google Health reports them.' : 'counted from the readings here.'}',
                if (value.sampleCount > value.samples.length)
                  'Drawn from ${value.samples.length} of ${value.sampleCount} readings.',
              ].join(' '),
              style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// The Beer sheet: the chart every other metric gets, plus the two ways to
// put a beer on a day that has already been and gone (ADR-024). The port of
// fitness-dashboard's web/components/DrinkDetail.tsx.
//
// The only detail sheet that writes as well as reads: beers have no sensor,
// so the chart is only as right as what someone remembered to tap in, and
// the fix belongs next to the evidence of the mistake. Two ways in, for two
// questions. The day rows under the chart are "last night was three, not
// two" — one tap, while the period shows days. The date picker is "that
// weekend in May", which no list of recent days can reach.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/actions.dart';
import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/key_metrics.dart';
import '../../domain/metric_about.dart';
import '../../domain/series.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'detail_sheet.dart';

class DrinkDetail extends ConsumerStatefulWidget {
  const DrinkDetail({super.key});

  @override
  ConsumerState<DrinkDetail> createState() => _DrinkDetailState();
}

class _DrinkDetailState extends ConsumerState<DrinkDetail> {
  List<DrinkDayOut>? _days;
  String? _loadError;
  String? _editError;
  var _period = Period.week;
  int? _active;
  final _today = startOfDay(DateTime.now());

  // How many writes are in the air per day. The stepper's rule: four taps
  // in a row must not wait on a round trip each, and only the last reply
  // still outstanding may replace the number on screen.
  final _inFlight = <String, int>{};

  DrinksApi get _drinks => ref.read(apiProvider).getDrinksApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final days = (await _drinks.listDays(days: historyDays)).data!;
      if (mounted) setState(() => _days = days);
    } catch (error) {
      if (mounted) setState(() => _loadError = describeError(error));
    }
  }

  /// Only touches a day the chart is holding: a date from the picker can be
  /// years outside the window, and inserting it would put a hole in a
  /// series that is dense by construction.
  void _patch(DateTime date, DrinkDayOut Function(DrinkDayOut day) change) {
    setState(() => _days = [for (final day in _days ?? <DrinkDayOut>[]) day.date == date ? change(day) : day]);
  }

  static DrinkDayOut _withCount(DrinkDayOut day, int count) =>
      DrinkDayOut(date: day.date, count: count, reported: day.reported, editable: day.editable);

  /// Write one day. Optimistic where the day is on screen, and rolled back
  /// to what was there if the server refuses it.
  Future<DrinkDayOut?> _saveDay(DrinkDayOut day, int next) async {
    if (next < day.reported || next > maxDrinksPerDay) return null;
    final key = dayKey(day.date);
    setState(() => _editError = null);
    _patch(day.date, (row) => _withCount(row, next));
    _inFlight[key] = (_inFlight[key] ?? 0) + 1;
    try {
      final saved = (await _drinks.setDay(
        day: day.date,
        drinkCountIn: DrinkCountIn(count: next),
      )).data!;
      if (mounted && _inFlight[key] == 1) _patch(day.date, (_) => saved);
      // Correcting a day no report has claimed yet can reach drinks still
      // on the stepper, so the counter can move under this sheet.
      ref.read(drinkStepperProvider.notifier).reread();
      return saved;
    } catch (error) {
      if (mounted) {
        _patch(day.date, (row) => _withCount(row, day.count));
        setState(() => _editError = describeError(error));
      }
      return null;
    } finally {
      _inFlight[key] = _inFlight[key]! - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final days = _days;
    final byDate = {for (final day in days ?? <DrinkDayOut>[]) dayKey(day.date): day};
    final spec = periodSpec(_period);
    final volumeL = ref.watch(dashboardProvider.select((s) => s.data.drinks?.volumeL));

    // Zeros inside the record are real: a dry day is nothing drunk, not a
    // sensor with nothing to say, so this is the one chart that plots them.
    // Before the record starts they are not — the counter has only existed
    // since ADR-019 — so the series starts at the first beer ever logged
    // and everything older plots as the gap it is. Those days stay
    // editable: filling one in is what makes it part of the record.
    final oldestFirst = (days ?? <DrinkDayOut>[]).reversed.toList();
    final begins = oldestFirst.indexWhere((day) => day.count > 0);
    final points = [
      for (final (i, day) in oldestFirst.indexed)
        (date: day.date, value: begins >= 0 && i >= begins ? day.count : null),
    ];
    final buckets = bucketSeries(points, _period, _today);

    return DetailSheet(
      title: beerMetric.title,
      period: _period,
      onPeriodChange: (next) => setState(() {
        _period = next;
        _active = null;
      }),
      children: [
        if (_loadError != null)
          Notice('Could not load history: $_loadError', tone: NoticeTone.error)
        else
          ChartPanel(
            metric: beerMetric,
            buckets: buckets,
            period: _period,
            today: _today,
            active: _active,
            onActiveChange: (i) => setState(() => _active = i),
            dim: days == null,
          ),
        if (_loadError == null && days != null && seriesAverage(buckets) == null)
          const Notice('No beers recorded in this period. Fill a day in below and it will appear.'),
        if (_editError != null) Notice(_editError!, tone: NoticeTone.error),
        _DayPicker(
          latestEditable: days?.where((day) => day.editable).firstOrNull?.date,
          known: byDate,
          volumeL: volumeL,
          onSave: _saveDay,
        ),
        const AboutPanel(about: beerAbout),
        HistoryList(
          heading: spec.long,
          rows: [
            for (final bucket in buckets.reversed)
              () {
                // A daily bucket *is* one day, so the row can carry the
                // stepper. A weekly or monthly one is an average of days
                // and has no single number to change.
                final day = spec.aggregate == Aggregate.daily ? byDate[bucket.key] : null;
                final label = bucketLabel(bucket, spec.aggregate, _today);
                return HistoryRow(
                  // Today says where its number lives in the label: it is a
                  // note about the day, and next to the count it would wrap.
                  label: day != null && !day.editable ? '$label · on the counter' : label,
                  value: day != null
                      ? _DayStepper(day: day, label: label, onSave: _saveDay)
                      : HistoryValue(bucket.value == null ? null : beerMetric.format(bucket.value!)),
                );
              }(),
          ],
        ),
        if (days == null && _loadError == null)
          Center(child: CircularProgressIndicator(color: p.primary.color, strokeWidth: 2)),
      ],
    );
  }
}

/// One day's count and its two steppers, as a history row's value.
///
/// Today gets the count alone: that evening is the counter's, and one night
/// with two numbers on it is how a beer gets logged twice. The minus stops
/// at what a report already counted — said in its tooltip, because a
/// disabled control with no reason is a bug as far as the user can tell.
class _DayStepper extends StatelessWidget {
  const _DayStepper({required this.day, required this.label, required this.onSave});

  final DrinkDayOut day;
  final String label;
  final Future<DrinkDayOut?> Function(DrinkDayOut day, int next) onSave;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final atFloor = day.count <= day.reported;
    final style = IconButton.styleFrom(
      backgroundColor: p.surfaceContainerHighest,
      foregroundColor: p.onSurface,
      minimumSize: const Size(36, 36),
      fixedSize: const Size(36, 36),
      padding: EdgeInsets.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '${day.count}',
            textAlign: TextAlign.center,
            style: TypeScale.titleMedium.copyWith(
              color: day.count > 0 ? p.onSurface : p.outline,
              fontFeatures: TypeScale.tabular,
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (day.editable) ...[
          IconButton(
            style: style,
            tooltip: atFloor
                ? 'One fewer beer on $label — not possible, a report already counted these'
                : 'One fewer beer on $label',
            onPressed: atFloor ? null : () => onSave(day, day.count - 1),
            icon: const Icon(Icons.remove, size: 18),
          ),
          const SizedBox(width: 4),
          IconButton(
            style: style,
            tooltip: 'One more beer on $label',
            onPressed: day.count >= maxDrinksPerDay ? null : () => onSave(day, day.count + 1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ] else
          // Keeps today's count in the same column as every other row's.
          const SizedBox(width: 76),
      ],
    );
  }
}

/// Any day, however far back: pick it from a calendar, type the number,
/// save (ADR-024). A typed count rather than a stepper, because a holiday
/// filled in a month late is "six", not six taps. The day is read back
/// before a number is offered, so saving an unchanged day is a no-op
/// rather than a silent overwrite of something forgotten.
class _DayPicker extends ConsumerStatefulWidget {
  const _DayPicker({required this.latestEditable, required this.known, required this.volumeL, required this.onSave});

  /// The newest day that may be written — yesterday, in the server's own
  /// zone. Caps the calendar, so today and tomorrow cannot be picked.
  final DateTime? latestEditable;

  /// The days the sheet already holds, so picking one costs no request.
  final Map<String, DrinkDayOut> known;
  final num? volumeL;
  final Future<DrinkDayOut?> Function(DrinkDayOut day, int next) onSave;

  @override
  ConsumerState<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends ConsumerState<_DayPicker> {
  DateTime? _date;
  DrinkDayOut? _day;
  final _typed = TextEditingController();
  bool _busy = false;
  String? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final last = widget.latestEditable ?? startOfDay(DateTime.now()).subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? last,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _day = null;
      _typed.text = '';
      _saved = null;
      _error = null;
    });
    final held = widget.known[dayKey(picked)];
    if (held != null) {
      setState(() {
        _day = held;
        _typed.text = '${held.count}';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final fetched = (await ref.read(apiProvider).getDrinksApi().getDay(day: picked)).data!;
      if (mounted && _date == picked) {
        setState(() {
          _day = fetched;
          _typed.text = '${fetched.count}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // Kept in step with the list while the card is open: a stepper tap on
    // the same date would otherwise leave this holding a stale count.
    final current = (_date == null ? null : widget.known[dayKey(_date!)]) ?? _day;
    final count = int.tryParse(_typed.text);
    final valid = count != null && count >= 0 && count <= maxDrinksPerDay;
    final belowFloor = current != null && valid && count < current.reported;
    final canSave = current != null && valid && !belowFloor && !_busy;

    Future<void> submit() async {
      if (!canSave) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final result = await widget.onSave(current, count);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (result != null) {
          _day = result;
          _saved = '${fmtDayFull(result.date)} · ${result.count == 1 ? '1 beer' : '${result.count} beers'}';
        } else {
          _error = 'Could not save that day';
        }
      });
    }

    final fieldDecoration = BoxDecoration(
      color: p.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(Shape.sm),
    );
    final small = TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant);

    // One line under the controls, in priority order: what went wrong,
    // what was saved, or what that day currently holds.
    final (String? line, bool isError) = _error != null
        ? (_error, true)
        : belowFloor
        ? ('A report already counted ${current.reported} that day, so it cannot go below that.', true)
        : _saved != null
        ? ('Saved · $_saved', false)
        : current != null
        ? (
            '${fmtDayFull(current.date)} · currently ${current.count == 0
                ? 'no beers'
                : widget.volumeL == null
                ? '${current.count}'
                : '${current.count} · ${fmtDrinkVolume(current.count, widget.volumeL!)}'}',
            false,
          )
        : (null, false);

    return SurfaceCard(
      radius: Shape.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fill in any day', style: TypeScale.titleSmall.copyWith(color: p.onSurface)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Day', style: small),
                    const SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pick,
                        borderRadius: BorderRadius.circular(Shape.sm),
                        child: Ink(
                          height: 44,
                          decoration: fieldDecoration,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _date == null ? 'Pick a day' : fmtDayFull(_date!),
                                  style: TypeScale.bodyMedium.copyWith(
                                    color: _date == null ? p.onSurfaceVariant : p.onSurface,
                                  ),
                                ),
                              ),
                              Icon(Icons.calendar_today, size: 18, color: p.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Beers', style: small),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: current == null ? 0.4 : 1,
                      child: Container(
                        height: 44,
                        decoration: fieldDecoration,
                        alignment: Alignment.center,
                        child: TextField(
                          controller: _typed,
                          enabled: current != null,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          onSubmitted: (_) => submit(),
                          style: TypeScale.bodyMedium.copyWith(color: p.onSurface, fontFeatures: TypeScale.tabular),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: FilledButton.tonal(onPressed: canSave ? submit : null, child: Text(_busy ? '…' : 'Save')),
              ),
            ],
          ),
          if (line != null) ...[
            const SizedBox(height: 8),
            Text(line, style: TypeScale.labelMedium.copyWith(color: isError ? p.error.color : p.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

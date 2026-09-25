// Everything the dashboard shows, loaded in one round of parallel requests
// — the port of fitness-dashboard's web/hooks/useDashboardData.ts.
//
// Every source settles on its own: one failing endpoint leaves the others
// on screen and records its own message, so a dead Gemini key does not
// blank the step count. The round repeats every five minutes. It only
// re-reads what the API has; pulling Google fresh is the sync chip's job
// (ADR-026), or a dashboard left open would hit Google every five minutes.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const autoRefresh = Duration(minutes: 5);

/// The generated API client. Overridden in main.dart with one whose Dio
/// carries the Firebase ID token.
final apiProvider = Provider<FitnessApi>((ref) => throw UnimplementedError('apiProvider is set in main.dart'));

/// How many days of health history the Health tab averages over.
final healthRangeProvider = NotifierProvider<HealthRange, int>(HealthRange.new);

class HealthRange extends Notifier<int> {
  static const options = [7, 30, 90];

  @override
  int build() => 7;

  void set(int days) => state = days;
}

class DashboardData {
  const DashboardData({
    this.matches = const [],
    this.missingMatch,
    this.events = const [],
    this.daily = const [],
    this.lastKnown,
    this.exercises = const [],
    this.report,
    this.training,
    this.drinks,
    this.calendarConnected = false,
    this.healthConnected = false,
  });

  final List<MatchOut> matches;

  /// Yesterday's fixture with no ÖFB game logged, or null.
  final MissingMatchOut? missingMatch;
  final List<CalendarEventOut> events;

  /// Oldest first, as the charts and "since yesterday" comparisons read it.
  final List<DailyHealthOut> daily;

  /// The last weight and VO2 max there were, whenever they were measured.
  final LatestMeasurementsOut? lastKnown;
  final List<ExerciseSessionOut> exercises;
  final AiReportOut? report;
  final TrainingStatusOut? training;
  final DrinkCounterOut? drinks;
  final bool calendarConnected;
  final bool healthConnected;

  DailyHealthOut? get latest => daily.isEmpty ? null : daily.last;
  DailyHealthOut? get previous => daily.length < 2 ? null : daily[daily.length - 2];

  /// The two fields something other than a refresh writes: a report New
  /// report generated, and the beer counter a tap moved.
  DashboardData copyWith({AiReportOut? Function()? report, DrinkCounterOut? Function()? drinks}) => DashboardData(
    matches: matches,
    missingMatch: missingMatch,
    events: events,
    daily: daily,
    lastKnown: lastKnown,
    exercises: exercises,
    report: report == null ? this.report : report(),
    training: training,
    drinks: drinks == null ? this.drinks : drinks(),
    calendarConnected: calendarConnected,
    healthConnected: healthConnected,
  );
}

/// One message per source that can fail on its own; null when it did not.
class DashboardErrors {
  const DashboardErrors({
    this.matches,
    this.events,
    this.daily,
    this.exercises,
    this.report,
    this.training,
    this.drinks,
  });

  final String? matches;
  final String? events;
  final String? daily;
  final String? exercises;
  final String? report;
  final String? training;
  final String? drinks;
}

class DashboardState {
  const DashboardState({
    this.data = const DashboardData(),
    this.errors = const DashboardErrors(),
    this.loading = false,
    this.reportLoaded = false,
    this.lastSynced,
    this.accessDenied = false,
    this.sessionRejected = false,
  });

  final DashboardData data;
  final DashboardErrors errors;

  /// True while a round is in flight, the five-minute ones included.
  final bool loading;

  /// Whether the report request has come back at least once, either way:
  /// the report card tells "still asking" apart from "there is none".
  final bool reportLoaded;
  final DateTime? lastSynced;

  /// The API answered 403: this Google account is not on the allowlist,
  /// and signing in again with it cannot help (ADR-029).
  final bool accessDenied;

  /// The API answered 401 although the app is signed in: the token was
  /// refused, and signing in again is the way out.
  final bool sessionRejected;
}

/// A failed request, in words for the screen.
String describeError(Object error) {
  if (error is DioException) {
    final response = error.response;
    if (response == null) return 'Could not reach the API';
    final data = response.data;
    final detail = data is Map && data['detail'] is String ? data['detail'] as String : null;
    return detail ?? 'HTTP ${response.statusCode}';
  }
  return 'Failed to read the API response';
}

bool _hasStatus(Object? error, int status) => error is DioException && error.response?.statusCode == status;

/// A request's outcome, kept rather than thrown, so one failure does not
/// cancel the round.
class _Settled<T> {
  _Settled.ok(this.value) : error = null;
  _Settled.failed(Object this.error) : value = null;

  final T? value;
  final Object? error;

  bool get ok => error == null;
  String? get message => error == null ? null : describeError(error!);
}

Future<_Settled<T>> _settle<T>(Future<Response<T>> request) async {
  try {
    return _Settled.ok((await request).data);
  } catch (error) {
    return _Settled.failed(error);
  }
}

final dashboardProvider = NotifierProvider<DashboardController, DashboardState>(DashboardController.new);

class DashboardController extends Notifier<DashboardState> {
  Timer? _timer;
  int _round = 0;

  @override
  DashboardState build() {
    _timer = Timer.periodic(autoRefresh, (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    // A new range re-reads, as the web does; the other sources ride along.
    ref.listen(healthRangeProvider, (_, _) => refresh());
    Future.microtask(refresh);
    return const DashboardState(loading: true);
  }

  FitnessApi get _api => ref.read(apiProvider);

  Future<void> refresh() async {
    final round = ++_round;
    state = DashboardState(
      data: state.data,
      errors: state.errors,
      loading: true,
      reportLoaded: state.reportLoaded,
      lastSynced: state.lastSynced,
      accessDenied: state.accessDenied,
      sessionRejected: state.sessionRejected,
    );

    final range = ref.read(healthRangeProvider);
    final api = _api;
    final health = api.getHealthApi();

    // The report is applied as soon as it lands: its headline is the
    // largest text on the Today tab, and /training/status (a year of daily
    // points) is the slowest request of the round.
    final reportRequest = _latestReport(api);
    unawaited(
      reportRequest.then((report) {
        if (round != _round || !report.ok) return;
        state = _copy(data: state.data.copyWith(report: () => report.value), reportLoaded: true);
      }),
    );

    // Two records because Future.wait on a record stops at nine; all ten
    // requests are already in flight before either is awaited.
    final schedule = (
      _settle(api.getMatchesApi().listMatches()),
      _settle(api.getMatchesApi().missingYesterday()),
      _settle(api.getCalendarApi().listUpcomingEvents()),
      _settle(api.getOauthApi().status()),
      _settle(health.listDailyHealth(limit: range)),
    );
    final rest = (
      _settle(health.latestHealthMeasurements()),
      _settle(health.listExercises()),
      reportRequest,
      _settle(api.getTrainingApi().trainingStatus()),
      _settle(api.getDrinksApi().getCounter()),
    );
    final (matches, missing, events, status, daily) = await schedule.wait;
    final (lastKnown, exercises, report, training, drinks) = await rest.wait;

    if (round != _round) return;
    final previous = state.data;
    final all = <_Settled<Object?>>[
      matches,
      missing,
      events,
      status,
      daily,
      lastKnown,
      exercises,
      report,
      training,
      drinks,
    ];

    state = DashboardState(
      data: DashboardData(
        matches: matches.ok ? matches.value! : previous.matches,
        missingMatch: missing.ok ? missing.value : previous.missingMatch,
        events: events.ok ? events.value! : previous.events,
        daily: daily.ok ? ([...daily.value!]..sort((a, b) => a.date.compareTo(b.date))) : previous.daily,
        lastKnown: lastKnown.ok ? lastKnown.value : previous.lastKnown,
        exercises: exercises.ok ? exercises.value! : previous.exercises,
        report: report.ok ? report.value : previous.report,
        training: training.ok ? training.value : previous.training,
        drinks: drinks.ok ? drinks.value : previous.drinks,
        calendarConnected: status.ok ? status.value!.calendar.connected : previous.calendarConnected,
        healthConnected: status.ok ? status.value!.health.connected : previous.healthConnected,
      ),
      errors: DashboardErrors(
        matches: matches.message,
        events: events.message,
        daily: daily.message,
        exercises: exercises.message,
        report: report.message,
        training: training.message,
        drinks: drinks.message,
      ),
      loading: false,
      reportLoaded: true,
      lastSynced: DateTime.now(),
      accessDenied: all.any((result) => _hasStatus(result.error, 403)),
      sessionRejected: all.any((result) => _hasStatus(result.error, 401)),
    );
  }

  /// Drop in a report New report generated, without a round trip.
  void setReport(AiReportOut report) =>
      state = _copy(data: state.data.copyWith(report: () => report), reportLoaded: true);

  /// Move the beer counter: optimistically on a tap, then to the server's
  /// answer (see DrinkStepper).
  void updateDrinks(DrinkCounterOut? Function(DrinkCounterOut? previous) change) =>
      state = _copy(data: state.data.copyWith(drinks: () => change(state.data.drinks)));

  /// Mark a scheduled session as missed, or undo it, then re-read: the load
  /// it changed is in the training status, not in the row that was tapped.
  Future<void> setSkipped(ExerciseSessionOut session, bool skipped) async {
    final source = switch (session.source_) {
      'match' => SkipInSource_Enum.match,
      'training' => SkipInSource_Enum.training,
      _ => throw ArgumentError('A ${session.source_} session cannot be skipped'),
    };
    await _api.getTrainingApi().setSkip(
      skipIn: SkipIn(source_: source, refId: session.refId!, skipped: skipped),
    );
    await refresh();
  }

  /// The consent URL for connecting Google Calendar or Health (ADR-029
  /// amendment): asked for with the ID token, then opened in a browser.
  Future<String> connectUrl(String target) async {
    final response = await _api.getOauthApi().login(target: target);
    return response.data!.url;
  }

  /// No report yet is a 404, which is an answer rather than a failure.
  Future<_Settled<AiReportOut?>> _latestReport(FitnessApi api) async {
    try {
      return _Settled.ok((await api.getReportsApi().getLatestReport()).data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return _Settled.ok(null);
      return _Settled.failed(error);
    } catch (error) {
      return _Settled.failed(error);
    }
  }

  DashboardState _copy({DashboardData? data, bool? reportLoaded}) => DashboardState(
    data: data ?? state.data,
    errors: state.errors,
    loading: state.loading,
    reportLoaded: reportLoaded ?? state.reportLoaded,
    lastSynced: state.lastSynced,
    accessDenied: state.accessDenied,
    sessionRejected: state.sessionRejected,
  );
}

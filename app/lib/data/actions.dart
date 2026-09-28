// The dashboard's writes and on-demand reads — the parts of
// fitness-dashboard's web/app/page.tsx that were not loading: the sync
// chip, New report, the beer stepper, and the histories a detail sheet
// fetches when it opens.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/slow_requests.dart';
import 'dashboard.dart';

// --- sync -------------------------------------------------------------------

class SyncState {
  const SyncState({this.syncing = false, this.problem});

  final bool syncing;

  /// What the last pull could not reach, shown under the header.
  final String? problem;
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  /// POST /sync — Google Health and the calendar, fresh. A source that
  /// failed goes under the header rather than being thrown: what did land
  /// is still worth showing and reporting on. Shared by the sync chip and
  /// New report.
  Future<void> pullGoogle() async {
    state = SyncState(syncing: state.syncing);
    String? problem;
    try {
      final response = await ref.read(apiProvider).getSyncApi().syncNow(extra: slowRequest);
      final failed = response.data!.sources.entries.where((e) => e.value != 'ok').map((e) => e.key).toList();
      if (failed.isNotEmpty) problem = 'Sync failed: ${failed.join(', ')}';
    } catch (error) {
      problem = describeError(error);
    }
    state = SyncState(syncing: state.syncing, problem: problem);
  }

  /// The header chip (ADR-026): pull, then re-read the dashboard even if
  /// the pull failed — the hourly sync's data is still worth showing. Only
  /// a tap does this; the five-minute refresh just re-reads.
  Future<void> syncNow() async {
    if (state.syncing) return;
    state = const SyncState(syncing: true);
    await pullGoogle();
    try {
      await ref.read(dashboardProvider.notifier).refresh();
    } finally {
      state = SyncState(problem: state.problem);
    }
  }
}

// --- New report ---------------------------------------------------------------

/// Which half of New report is running: the Google sync, then Gemini.
enum ReportPhase { syncing, analyzing }

class NewReportState {
  const NewReportState({this.phase, this.error});

  final ReportPhase? phase;
  final String? error;
}

final newReportProvider = NotifierProvider<NewReportController, NewReportState>(NewReportController.new);

class NewReportController extends Notifier<NewReportState> {
  @override
  NewReportState build() => const NewReportState();

  /// **New report**, the one report button (ADR-027): pull Google Health
  /// and the calendar fresh — a long night's sleep lands late — and then
  /// report on it. Two requests rather than one, so the button can say
  /// which it is waiting on.
  ///
  /// The dashboard is re-read afterwards even if the report failed: the
  /// sync has changed the tiles either way, and on success the beer counter
  /// shows that the day's first report took it (ADR-019).
  Future<void> run() async {
    if (state.phase != null) return;
    state = const NewReportState(phase: ReportPhase.syncing);
    await ref.read(syncProvider.notifier).pullGoogle();
    state = const NewReportState(phase: ReportPhase.analyzing);
    String? error;
    final dashboard = ref.read(dashboardProvider.notifier);
    try {
      final response = await ref.read(apiProvider).getReportsApi().generateReport(extra: slowRequest);
      dashboard.setReport(response.data!);
    } catch (e) {
      error = describeError(e);
    }
    try {
      await dashboard.refresh();
    } finally {
      state = NewReportState(error: error);
    }
  }
}

// --- the beer stepper -----------------------------------------------------------

/// The most beers a day can hold, the server's own bound (a count over it
/// comes back 422), applied here so a control never sends a request it
/// already knows will be refused.
const maxDrinksPerDay = 99;

final drinkStepperProvider = NotifierProvider<DrinkStepper, String?>(DrinkStepper.new);

/// The Today tile's writes (ADR-019). The state is the last error, if any.
///
/// Optimistic, and deliberately not serialised behind a lock: six beers is
/// six taps in a row, and a stepper that waits for a round trip between
/// them is a stepper you tap twice. Each tap moves the number straight
/// away, and only the last request still in flight may replace it with the
/// server's — an earlier reply landing late would roll the count backwards.
class DrinkStepper extends Notifier<String?> {
  int _inFlight = 0;

  @override
  String? build() => null;

  DashboardController get _dashboard => ref.read(dashboardProvider.notifier);
  DrinksApi get _drinks => ref.read(apiProvider).getDrinksApi();

  static DrinkCounterOut? _withCount(DrinkCounterOut? counter, int count) => counter == null
      ? null
      : DrinkCounterOut(
          count: count,
          volumeL: counter.volumeL,
          alcoholGrams: counter.alcoholGrams,
          firstLoggedAt: counter.firstLoggedAt,
          lastLoggedAt: counter.lastLoggedAt,
        );

  int get _count => ref.read(dashboardProvider).data.drinks?.count ?? 0;

  /// One beer up or down. A failed tap takes back its own delta rather
  /// than restoring a snapshot, so it does not undo the taps that landed
  /// while it was away.
  Future<void> change(int delta) async {
    if (delta < 0 && _count == 0) return;
    await _write(
      apply: (count) => count + delta < 0 ? 0 : count + delta,
      undo: (count) => count - delta < 0 ? 0 : count - delta,
      request: () => delta > 0 ? _drinks.addDrink() : _drinks.undoDrink(),
    );
  }

  /// A count typed into the tile rather than tapped up to. Through the same
  /// in-flight bookkeeping, so a number typed while a +1 is still in the air
  /// cannot be overwritten by that reply.
  Future<void> set(int count) async {
    final before = _count;
    await _write(
      apply: (_) => count,
      undo: (_) => before,
      request: () => _drinks.setCounter(drinkCountIn: DrinkCountIn(count: count)),
    );
  }

  Future<void> _write({
    required int Function(int count) apply,
    required int Function(int count) undo,
    required Future<Response<DrinkCounterOut>> Function() request,
  }) async {
    state = null;
    _dashboard.updateDrinks((counter) => _withCount(counter, apply(counter?.count ?? 0)));
    _inFlight++;
    try {
      final counter = (await request()).data!;
      if (_inFlight == 1) _dashboard.updateDrinks((_) => counter);
    } catch (error) {
      _dashboard.updateDrinks((counter) => _withCount(counter, undo(counter?.count ?? 0)));
      state = describeError(error);
    } finally {
      _inFlight--;
    }
  }

  /// Re-read the counter after a day was filled in or corrected: correcting
  /// yesterday down can reach drinks that are still on the stepper while no
  /// report has claimed them, and the server knows the new number.
  Future<void> reread() async {
    try {
      final counter = (await _drinks.getCounter()).data!;
      _dashboard.updateDrinks((_) => counter);
    } catch (_) {
      // The tile keeps what it had; the next refresh corrects it.
    }
  }
}

// --- histories a sheet fetches when it opens --------------------------------------

/// A year is the longest window a sheet offers, so one request covers every
/// period and switching between them costs nothing.
const historyDays = 366;

final healthHistoryProvider = AsyncNotifierProvider<HealthHistory, List<DailyHealthOut>>(HealthHistory.new);

/// The year of health rows the metric sheets plot. Kept out of the
/// dashboard's round on purpose: most sessions never open a sheet, and a
/// year of rows on every load would cost the tiles. Fetched when a sheet
/// first asks, then again only once it has gone stale — the dashboard's
/// own five minutes, so a sheet shows what the tiles do.
class HealthHistory extends AsyncNotifier<List<DailyHealthOut>> {
  DateTime? _fetchedAt;

  @override
  Future<List<DailyHealthOut>> build() async {
    final rows = (await ref.read(apiProvider).getHealthApi().listDailyHealth(limit: historyDays)).data!;
    _fetchedAt = DateTime.now();
    return [...rows]..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Called when a sheet opens: re-fetch if what is held is stale.
  void ensureFresh() {
    final at = _fetchedAt;
    if (at != null && DateTime.now().difference(at) >= autoRefresh && !state.isLoading) ref.invalidateSelf();
  }
}

/// One session's heart rate trace, fetched when its sheet opens. A few
/// hundred points per session, so never with the list.
///
/// The id is escaped here because the generated client puts path
/// parameters in raw, and a session id is "2026-09-24#0": unescaped, the
/// "#" starts a URL fragment and the request goes to the day instead.
final sessionHeartRateProvider = FutureProvider.autoDispose.family<SessionHeartRateOut, String>(
  (ref, sessionId) async => (await ref
      .read(apiProvider)
      .getHealthApi()
      .exerciseHeartRate(sessionId: Uri.encodeComponent(sessionId))).data!,
);

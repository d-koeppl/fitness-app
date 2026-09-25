// The report-ready push, on the app's side (ADR-030): asking for
// permission, keeping the server's copy of this device's FCM token current,
// and bringing the new report onto the screen when a push arrives or is
// tapped. The server sends only one push, the automatic evening report.

import 'dart:async';

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../push/push_service.dart';
import 'dashboard.dart';

/// Null where there is no push: iOS for now, and the widget tests.
final pushServiceProvider = Provider<PushService?>((ref) => null);

enum PushStatus {
  /// No push on this platform or in this browser.
  unsupported,

  /// Finding out, or asking.
  checking,

  /// Not asked yet, or switched off: the header offers to turn it on.
  off,

  /// Refused; only the system or browser settings can undo that.
  blocked,

  on,
}

class PushState {
  const PushState(this.status, {this.problem, this.taps = 0, this.arrival});

  final PushStatus status;

  /// Why turning notifications on did not work, shown under the header.
  final String? problem;

  /// Counts taps on a push, so the shell can switch to the report each time.
  final int taps;

  /// The latest push that arrived with the app in front, for a snackbar.
  final PushArrival? arrival;

  PushState copyWith({PushStatus? status, String? Function()? problem, int? taps, PushArrival? arrival}) => PushState(
    status ?? this.status,
    problem: problem == null ? this.problem : problem(),
    taps: taps ?? this.taps,
    arrival: arrival ?? this.arrival,
  );
}

final pushProvider = NotifierProvider<PushController, PushState>(PushController.new);

class PushController extends Notifier<PushState> {
  PushService? get _service => ref.read(pushServiceProvider);

  @override
  PushState build() {
    final service = ref.watch(pushServiceProvider);
    if (service == null) return const PushState(PushStatus.unsupported);

    final subscriptions = [
      // FCM may rotate the token; the server must have the current one.
      service.tokenRefreshes.listen((token) async {
        if (state.status != PushStatus.on) return;
        try {
          await _register(token);
        } catch (_) {
          // The next start registers whatever the token is then.
        }
      }),
      service.arrivals.listen(_arrived),
      service.taps.listen((_) => _tapped()),
    ];
    // In a browser, a click on the notification only focuses the tab; the
    // page hears nothing of it. So coming back to the app re-reads the
    // report, which is one small request.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (state.status == PushStatus.on) unawaited(ref.read(dashboardProvider.notifier).refreshReport());
      },
    );
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      lifecycle.dispose();
    });

    Future.microtask(_start);
    return const PushState(PushStatus.checking);
  }

  Future<void> _start() async {
    final service = _service!;
    try {
      if (!await service.supported()) {
        state = state.copyWith(status: PushStatus.unsupported);
        return;
      }
      if (await service.launchedByTap()) _tapped();
      final permission = await service.permission();
      if (permission == PushPermission.granted) {
        // Every start, not just the first: the token may have changed
        // while the app was closed.
        await _turnOn();
        return;
      }
      state = state.copyWith(status: permission == PushPermission.denied ? PushStatus.blocked : PushStatus.off);
      // Perhaps switched off in the settings since the last start: drop
      // any token, so the server's next send prunes it.
      unawaited(service.deleteToken().catchError((_) {}));
    } catch (_) {
      state = state.copyWith(status: PushStatus.unsupported);
    }
  }

  /// The header's bell: ask, then register.
  Future<void> enable() async {
    final service = _service;
    if (service == null) return;
    state = state.copyWith(status: PushStatus.checking, problem: () => null);
    try {
      switch (await service.requestPermission()) {
        case PushPermission.granted:
          await _turnOn();
        case PushPermission.denied:
          state = state.copyWith(status: PushStatus.blocked);
        case PushPermission.undecided:
          state = state.copyWith(status: PushStatus.off);
      }
    } catch (_) {
      state = state.copyWith(status: PushStatus.off, problem: () => 'Could not turn on notifications');
    }
  }

  Future<void> _turnOn() async {
    final String? token;
    try {
      token = await _service!.token();
    } catch (_) {
      state = state.copyWith(status: PushStatus.off, problem: () => 'Could not get a notification token');
      return;
    }
    if (token == null) {
      state = state.copyWith(status: PushStatus.off, problem: () => 'Could not get a notification token');
      return;
    }
    try {
      await _register(token);
      state = state.copyWith(status: PushStatus.on, problem: () => null);
    } catch (error) {
      state = state.copyWith(
        status: PushStatus.off,
        problem: () => 'Could not turn on notifications: ${describeError(error)}',
      );
    }
  }

  Future<void> _register(String token) => ref
      .read(apiProvider)
      .getPushApi()
      .registerPushDevice(
        pushDeviceIn: PushDeviceIn(
          token: token,
          platform: _service!.platform == 'web' ? PushDeviceInPlatformEnum.web : PushDeviceInPlatformEnum.android,
        ),
      );

  /// Before signing out: this device should stop getting another account's
  /// reports. Never throws, and gives up after a few seconds: signing out
  /// must work offline too, and a token deleted here is pruned by the
  /// server's next send even if the request below never arrived.
  Future<void> beforeSignOut() async {
    final service = _service;
    if (service == null || state.status != PushStatus.on) return;
    try {
      final token = await service.token();
      if (token != null) {
        await ref
            .read(apiProvider)
            .getPushApi()
            .unregisterPushDevice(pushTokenIn: PushTokenIn(token: token))
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // See above.
    }
    try {
      await service.deleteToken();
    } catch (_) {
      // Nothing left to do.
    }
    state = state.copyWith(status: PushStatus.off);
  }

  void _arrived(PushArrival arrival) {
    unawaited(ref.read(dashboardProvider.notifier).refreshReport());
    state = state.copyWith(arrival: arrival);
  }

  void _tapped() {
    unawaited(ref.read(dashboardProvider.notifier).refreshReport());
    state = state.copyWith(taps: state.taps + 1);
  }
}

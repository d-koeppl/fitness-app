// The dashboard shell: header, the four tabs, and the navigation — ported
// from fitness-dashboard's web/app/page.tsx. A bottom bar on a phone, a
// sidebar from the web's `lg` width (1024 px) up, which is how the browser
// build on the PC looks like the web app did.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/actions.dart';
import '../data/dashboard.dart';
import '../data/push.dart';
import '../domain/format.dart';
import 'tabs/coach_tab.dart';
import 'tabs/fitness_tab.dart';
import 'tabs/health_tab.dart';
import 'tabs/today_tab.dart';
import 'theme/palette.dart';

enum AppTab {
  today('Today', Icons.wb_twilight),
  fitness('Fitness', Icons.directions_run),
  health('Health', Icons.favorite_outline),
  coach('Coach', Icons.chat_bubble_outline);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _wide = 1024.0;

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key, required this.email, required this.signOut});

  /// The signed-in account, for the avatar's initial and its menu.
  final String? email;
  final Future<void> Function() signOut;

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  AppTab _tab = AppTab.today;

  // A tab is built the first time it is opened and then kept, so switching
  // back is instant and keeps its scroll position.
  final Set<AppTab> _opened = {AppTab.today};

  void _open(AppTab tab) => setState(() {
    _tab = tab;
    _opened.add(tab);
  });

  /// Sign-out drops this device from the report push first (ADR-030).
  Future<void> _signOut() async {
    await ref.read(pushProvider.notifier).beforeSignOut();
    await widget.signOut();
  }

  void _onPush(PushState? previous, PushState next) {
    // A tap on the push: the report is on Today.
    if (next.taps != (previous?.taps ?? 0)) _open(AppTab.today);
    // With the app in front the system shows nothing, so say it here.
    final arrival = next.arrival;
    if (arrival != null && !identical(arrival, previous?.arrival)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(arrival.body.isEmpty ? arrival.title : '${arrival.title}: ${arrival.body}'),
          // A snackbar with an action otherwise stays until dismissed
          // (found on the emulator); this one is news, not a question.
          persist: false,
          action: _tab == AppTab.today ? null : SnackBarAction(label: 'Open', onPressed: () => _open(AppTab.today)),
        ),
      );
    }
  }

  void _onBell(PushStatus status) {
    if (status == PushStatus.blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications are blocked. Allow them in the system or browser settings.')),
      );
      return;
    }
    ref.read(pushProvider.notifier).enable();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final sync = ref.watch(syncProvider);
    final push = ref.watch(pushProvider);
    ref.listen(pushProvider, _onPush);
    final p = Palette.of(context);
    if (state.accessDenied) {
      return _SignOutScreen(
        icon: Icons.block,
        message: widget.email == null ? 'This Google account is not allowed.' : '${widget.email} is not allowed.',
        signOut: widget.signOut,
      );
    }
    if (state.sessionRejected) {
      return _SignOutScreen(
        icon: Icons.lock_clock,
        message: 'Your session was not accepted. Sign in again.',
        signOut: widget.signOut,
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _wide;
    final maxContent = !wide ? 460.0 : (width >= 1280 ? 900.0 : 720.0);

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContent),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _Header(
                wide: wide,
                busy: state.loading || sync.syncing,
                lastSynced: state.lastSynced,
                email: widget.email,
                // The header chip (ADR-026): pull Google fresh, then re-read.
                onSync: ref.read(syncProvider.notifier).syncNow,
                push: push.status,
                onBell: () => _onBell(push.status),
                signOut: _signOut,
              ),
            ),
            for (final problem in [sync.problem, push.problem])
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(problem, style: TypeScale.labelSmall.copyWith(color: p.error.color)),
                  ),
                ),
            const SizedBox(height: 16),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: [
                  for (final tab in AppTab.values)
                    _opened.contains(tab) ? _TabPage(tab: tab, bottomGutter: wide ? 40 : 24) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 24),
              SizedBox(
                width: 240,
                child: _Sidebar(selected: _tab, onSelect: _open),
              ),
              const SizedBox(width: 24),
              Expanded(child: content),
              const SizedBox(width: 24),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => _open(AppTab.values[i]),
        backgroundColor: p.surfaceContainerHigh,
        indicatorColor: p.secondary.container,
        destinations: [for (final tab in AppTab.values) NavigationDestination(icon: Icon(tab.icon), label: tab.label)],
      ),
    );
  }
}

class _TabPage extends ConsumerWidget {
  const _TabPage({required this.tab, required this.bottomGutter});

  final AppTab tab;
  final double bottomGutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull to re-read, as the five-minute refresh does; it does not sync.
    return RefreshIndicator(
      onRefresh: ref.read(dashboardProvider.notifier).refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomGutter),
        child: switch (tab) {
          AppTab.today => const TodayTab(),
          AppTab.fitness => const FitnessTab(),
          AppTab.health => const HealthTab(),
          AppTab.coach => const CoachTab(),
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.busy,
    required this.lastSynced,
    required this.email,
    required this.onSync,
    required this.push,
    required this.onBell,
    required this.signOut,
  });

  final bool wide;
  final bool busy;
  final DateTime? lastSynced;
  final String? email;
  final VoidCallback onSync;

  /// The bell shows until notifications are on, as the web app's did.
  final PushStatus push;
  final VoidCallback onBell;
  final Future<void> Function() signOut;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final chipLabel = busy ? 'Syncing…' : (lastSynced != null ? fmtTime(lastSynced) : 'Sync');
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Material(
            color: p.surfaceContainerHighest,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: busy ? null : onSync,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    busy
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: p.onSurface),
                          )
                        : Icon(Icons.refresh, size: 16, color: p.onSurface),
                    const SizedBox(width: 8),
                    Text(chipLabel, style: TypeScale.labelLarge.copyWith(color: p.onSurface)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: wide
                ? const SizedBox.shrink()
                : Text(
                    'Fitness',
                    textAlign: TextAlign.center,
                    style: TypeScale.titleLarge.copyWith(color: p.onSurface),
                  ),
          ),
          if (push == PushStatus.off || push == PushStatus.blocked)
            IconButton(
              tooltip: push == PushStatus.blocked ? 'Notifications are blocked' : 'Turn on notifications',
              onPressed: onBell,
              icon: Icon(
                push == PushStatus.blocked ? Icons.notifications_off_outlined : Icons.notifications_none,
                color: p.onSurfaceVariant,
              ),
            ),
          PopupMenuButton<void>(
            tooltip: email ?? 'Account',
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [
              if (email != null) PopupMenuItem<void>(enabled: false, child: Text(email!)),
              PopupMenuItem<void>(onTap: signOut, child: const Text('Sign out')),
            ],
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.primary.container, shape: BoxShape.circle),
              child: Text(
                (email?.isNotEmpty ?? false) ? email![0].toUpperCase() : '?',
                style: TypeScale.labelLarge.copyWith(color: p.primary.onContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Text('Fitness', style: TypeScale.titleLarge.copyWith(color: p.onSurface)),
          ),
          for (final tab in AppTab.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: tab == selected ? p.secondary.container : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(tab),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(tab.icon, size: 24, color: tab == selected ? p.secondary.onContainer : p.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(
                          tab.label,
                          style: TypeScale.labelLarge.copyWith(
                            color: tab == selected ? p.secondary.onContainer : p.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The API refused the session: a 403 means the account is not on the
/// allowlist and only another account helps, a 401 that the token was not
/// accepted. Either way the way on is signing out (ADR-029).
class _SignOutScreen extends StatelessWidget {
  const _SignOutScreen({required this.icon, required this.message, required this.signOut});

  final IconData icon;
  final String message;
  final Future<void> Function() signOut;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: p.error.color),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TypeScale.titleMedium.copyWith(color: p.onSurface),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Training status, the sessions behind it, the week ahead, every match
// and the league table, one at a time — ported from fitness-dashboard's
// web/components/tabs/FitnessTab.tsx. The session sheet and the load
// history sheet arrive in phase 5.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard.dart';
import '../../domain/format.dart';
import '../../domain/league.dart';
import '../sheets/detail_sheet.dart';
import '../sheets/exercise_detail.dart';
import '../sheets/training_detail.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import '../widgets/training_status_card.dart';

enum FitnessSegment {
  training('Training'),
  sessions('Sessions'),
  upcoming('Upcoming'),
  matches('Matches'),
  table('Table');

  const FitnessSegment(this.label);
  final String label;
}

final fitnessSegmentProvider = NotifierProvider<_Segment, FitnessSegment>(_Segment.new);

class _Segment extends Notifier<FitnessSegment> {
  @override
  FitnessSegment build() => FitnessSegment.training;

  void set(FitnessSegment segment) => state = segment;
}

class FitnessTab extends ConsumerWidget {
  const FitnessTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(fitnessSegmentProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedPills(
          options: FitnessSegment.values,
          selected: segment,
          label: (s) => s.label,
          onSelect: ref.read(fitnessSegmentProvider.notifier).set,
        ),
        const SizedBox(height: 16),
        switch (segment) {
          FitnessSegment.training => const _Training(),
          FitnessSegment.sessions => const _Sessions(),
          FitnessSegment.upcoming => const _Upcoming(),
          FitnessSegment.matches => const _Matches(),
          FitnessSegment.table => const _Table(),
        },
      ],
    );
  }
}

class _Training extends ConsumerWidget {
  const _Training();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final error = state.errors.training;
    final training = state.data.training;
    if (error != null) return Notice('Could not load training status: $error', tone: NoticeTone.error);
    if (training == null) return const Notice('Working out your training status…');
    return TrainingStatusCard(data: training, onOpenDetail: () => openSheet(context, const TrainingDetail()));
  }
}

/// A list of rows on the surface colour: one column on a phone, two from
/// the web's `lg` width up.
class _RowList extends StatelessWidget {
  const _RowList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 700;
        final gap = twoColumns ? 12.0 : 8.0;
        final width = twoColumns ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.leading, required this.title, required this.subtitle, this.trailing, this.onTap});

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.of(context).surface,
      borderRadius: BorderRadius.circular(Shape.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: title),
                        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                      ],
                    ),
                    const SizedBox(height: 2),
                    subtitle,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Thu 04 Sept · 48 min · 150 bpm": [parts] joined by middots, then
/// [extras] (a chip, a card) with no dot before them, as on the web.
Widget _meta(BuildContext context, List<Widget> parts, [List<Widget> extras = const []]) {
  final p = Palette.of(context);
  final style = TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant);
  return DefaultTextStyle(
    style: style,
    child: Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, part) in parts.indexed) ...[if (i > 0) const Text('·'), part],
        ...extras,
      ],
    ),
  );
}

class _Sessions extends ConsumerWidget {
  const _Sessions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final exercises = state.data.exercises;
    final error = state.errors.exercises;

    final Widget body;
    if (!state.data.healthConnected) {
      body = ConnectCard(
        text: 'Connect Google Health to see your tracked sessions.',
        consentUrl: () => ref.read(dashboardProvider.notifier).connectUrl('health'),
      );
    } else if (error != null) {
      body = Notice('Could not load exercises: $error', tone: NoticeTone.error);
    } else if (exercises.isEmpty) {
      body = const Notice(
        'No sessions yet — the watch logs one for every workout it records, and a match or training '
        'it misses is listed from your schedule instead.',
      );
    } else {
      body = _RowList(children: [for (final session in exercises) _SessionRow(session)]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const SectionTitle('Latest exercises'), body],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(this.session);

  final ExerciseSessionOut session;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // An estimated session gets a different pill, dimmed once skipped.
    final estimated = session.source_ != 'tracked';
    final strike = session.skipped ? TextDecoration.lineThrough : null;
    return _ListRow(
      onTap: () => openSheet(context, ExerciseDetail(session: session)),
      leading: Opacity(
        opacity: session.skipped ? 0.5 : 1,
        child: IconDisc(
          icon: session.source_ == 'match' || session.match != null
              ? Icons.emoji_events_outlined
              : Icons.directions_run,
          background: estimated ? p.secondary.container : p.tertiary.container,
          color: estimated ? p.secondary.onContainer : p.tertiary.onContainer,
        ),
      ),
      title: Text(
        sessionTitle(session),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TypeScale.titleSmall.copyWith(color: p.onSurface, decoration: strike),
      ),
      // Active Zone Minutes, the unit the training load is in.
      trailing: Text(
        fmtSessionLoad(session),
        style: TypeScale.bodyMedium.copyWith(
          color: p.onSurfaceVariant,
          decoration: strike,
          fontFeatures: TypeScale.tabular,
        ),
      ),
      subtitle: _meta(
        context,
        [
          Text(fmtDate(session.startTs ?? session.date)),
          Text(fmtDuration(session.durationMinutes)),
          if (session.averageHeartRate != null) Text('${jsRound(session.averageHeartRate!)} bpm'),
        ],
        [
          if (estimated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: ShapeDecoration(
                color: session.skipped ? p.surfaceContainerHighest : p.secondary.container,
                shape: const StadiumBorder(),
              ),
              child: Text(
                session.skipped ? 'Skipped' : 'Not tracked',
                style: TextStyle(color: session.skipped ? p.onSurfaceVariant : p.secondary.onContainer),
              ),
            ),
        ],
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final error = state.errors.events;

    // The next seven days, counted from the last refresh rather than the
    // clock, as the web does, so the list only changes when data lands.
    final now = state.lastSynced ?? DateTime.fromMillisecondsSinceEpoch(0);
    final horizon = now.add(const Duration(days: 7));
    final events = state.data.events.where((e) {
      final start = e.startTs;
      return start != null && !start.isBefore(now) && !start.isAfter(horizon);
    }).toList();

    final Widget body;
    if (!state.data.calendarConnected) {
      body = ConnectCard(
        text: 'Connect Google Calendar to see events.',
        consentUrl: () => ref.read(dashboardProvider.notifier).connectUrl('calendar'),
      );
    } else if (error != null) {
      body = Notice('Could not load calendar events: $error', tone: NoticeTone.error);
    } else if (events.isEmpty) {
      body = const Notice('No upcoming events in the next 7 days.');
    } else {
      body = _RowList(
        children: [for (final event in events) _eventRow(context, event, fixtureForEvent(event, state.data.fixtures))],
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionTitle('Upcoming'), body]);
  }

  Widget _eventRow(BuildContext context, CalendarEventOut event, FixtureOut? fixture) {
    final p = Palette.of(context);
    final standing = fixture?.opponentStanding;
    return _ListRow(
      leading: IconDisc(
        icon: fixture != null ? Icons.emoji_events_outlined : Icons.calendar_today_outlined,
        background: p.primary.container,
        color: p.primary.onContainer,
      ),
      title: Text(
        event.title ?? '(untitled)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TypeScale.titleSmall.copyWith(color: p.onSurface),
      ),
      subtitle: standing == null
          ? Text(
              '${fmtEventWhen(event)}${event.location != null ? ' · ${event.location}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
            )
          // A match: where the opponent stands instead of the venue.
          : _meta(
              context,
              [Text(fmtEventWhen(event)), Text(fmtStanding(standing))],
              [_StrengthChip(standing.strength)],
            ),
    );
  }
}

class _Matches extends ConsumerWidget {
  const _Matches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final p = Palette.of(context);
    final matches = state.data.matches;
    final error = state.errors.matches;

    final Widget body;
    if (error != null) {
      body = Notice('Could not load matches: $error', tone: NoticeTone.error);
    } else if (matches.isEmpty) {
      body = const Notice('No matches yet. The ÖFB match reports are checked every night at 03:30.');
    } else {
      body = Column(
        children: [
          for (final match in matches) Padding(padding: const EdgeInsets.only(bottom: 8), child: _MatchRow(match)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Match performance',
          action: matches.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: ShapeDecoration(color: p.surface, shape: const StadiumBorder()),
                  child: Text(seasonForm(matches), style: TypeScale.labelMedium.copyWith(color: p.onSurface)),
                ),
        ),
        body,
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow(this.match);

  final MatchOut match;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sessionId = match.sessionId;
    return _ListRow(
      // The session this match was — tracked, or the estimate for one the
      // watch missed. Null for an untracked match on the bench, or one from
      // before the first tracked day: nothing to open.
      onTap: sessionId == null
          ? null
          : () => openSheet(context, ExerciseDetailById(sessionId: sessionId, title: matchTitle(match))),
      leading: OutcomeBadge(letter: matchOutcome(match).letter),
      title: Text(
        matchTitle(match),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TypeScale.titleSmall.copyWith(color: p.onSurface),
      ),
      trailing: Text(
        match.result ?? dash,
        style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant, fontFeatures: TypeScale.tabular),
      ),
      subtitle: _meta(
        context,
        [
          Text(fmtDate(match.matchDate)),
          Text("${match.minutesPlayed}'"),
          if (match.goals > 0) Text('${match.goals} goal${match.goals > 1 ? 's' : ''}'),
          if (match.opponentStanding case final standing?) _MatchStanding(standing),
        ],
        [
          if (match.yellowCard) const Tooltip(message: 'Yellow card', child: Text('🟨')),
          if (match.redCard) const Tooltip(message: 'Red card', child: Text('🟥')),
        ],
      ),
    );
  }
}

/// "was 3rd": where the opponent stood before kick-off, or "now 3rd" for a
/// match older than every stored table, where only today's rank is known.
class _MatchStanding extends StatelessWidget {
  const _MatchStanding(this.standing);

  final OpponentStandingOut standing;

  @override
  Widget build(BuildContext context) {
    final gap = fmtPointsGap(standing.pointsGap);
    final when = standing.atKickoff ? 'Before kick-off' : 'Today (no table from before this match)';
    return Tooltip(
      message: '$when: ${fmtStanding(standing)}${gap == null ? '' : ', $gap'}',
      child: Text('${standing.atKickoff ? 'was' : 'now'} ${fmtOrdinal(standing.rank)}'),
    );
  }
}

/// "Stronger" / "Level" / "Weaker" on points per game; nothing before both
/// sides have played.
class _StrengthChip extends StatelessWidget {
  const _StrengthChip(this.strength);

  final String? strength;

  @override
  Widget build(BuildContext context) {
    final label = strengthLabel(strength);
    if (label == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    final (bg, fg) = switch (strength) {
      'stronger' => (p.warning.container, p.warning.onContainer),
      'weaker' => (p.success.container, p.success.onContainer),
      _ => (p.surfaceContainerHighest, p.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(label, style: TextStyle(color: fg)),
    );
  }
}

/// The next fixtures with the opponent's standing, then the league table
/// as the ÖFB site has it, our row picked out.
class _Table extends ConsumerWidget {
  const _Table();

  /// Enough to see past the next weekend.
  static const _fixtureCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final p = Palette.of(context);
    final table = state.data.league;
    final error = state.errors.league;
    final fixtures = state.data.fixtures.take(_fixtureCount).toList();

    if (error != null && table == null) {
      return Notice('Could not load the league table: $error', tone: NoticeTone.error);
    }
    if (table == null) {
      return const Notice('No league table yet. It is read from the ÖFB site every night at 03:30.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fixtures.isNotEmpty) ...[
          const SectionTitle('Next matches'),
          _RowList(children: [for (final fixture in fixtures) _FixtureRow(fixture)]),
          const SizedBox(height: 24),
        ],
        SectionTitle(
          table.league,
          action: Text('as of ${fmtDate(table.day)}', style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
        ),
        _LeagueTable(table),
      ],
    );
  }
}

class _FixtureRow extends StatelessWidget {
  const _FixtureRow(this.fixture);

  final FixtureOut fixture;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final standing = fixture.opponentStanding;
    final gap = standing == null ? null : fmtPointsGap(standing.pointsGap);
    return _ListRow(
      leading: IconDisc(
        icon: Icons.emoji_events_outlined,
        background: p.primary.container,
        color: p.primary.onContainer,
      ),
      title: Text(
        fixtureTitle(fixture),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TypeScale.titleSmall.copyWith(color: p.onSurface),
      ),
      trailing: standing == null
          ? null
          : Text(
              fmtStanding(standing),
              style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant, fontFeatures: TypeScale.tabular),
            ),
      subtitle: _meta(
        context,
        [
          Text(fmtKickoff(fixture)),
          if (standing == null && fixture.art != null) Text(fixture.art!),
          if (gap != null) Text(gap),
        ],
        [if (standing != null) _StrengthChip(standing.strength)],
      ),
    );
  }
}

/// The table itself. Won / drawn / lost only where there is room for them:
/// on a phone the team names need the width more.
class _LeagueTable extends StatelessWidget {
  const _LeagueTable(this.table);

  final LeagueTableOut table;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        Widget cells(List<(String, double)> values, TextStyle style) => Row(
          children: [
            for (final (i, (text, width)) in values.indexed)
              if (i == 2)
                Expanded(
                  child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                )
              else
                SizedBox(
                  width: width,
                  child: Text(
                    text,
                    textAlign: i < 2 ? TextAlign.start : TextAlign.end,
                    style: style.copyWith(fontFeatures: TypeScale.tabular),
                  ),
                ),
          ],
        );

        List<(String, double)> columns(List<String> v) => [
          (v[0], 28),
          (v[1], 30),
          (v[2], 0),
          (v[3], 28),
          if (wide) ...[(v[4], 28), (v[5], 28), (v[6], 28)],
          (v[7], 52),
          (v[8], 40),
          (v[9], 36),
        ];

        final header = TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant, fontWeight: FontWeight.w600);
        final body = TypeScale.bodyMedium.copyWith(color: p.onSurface);
        return Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(Shape.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: cells(columns(['#', '', 'Team', 'P', 'W', 'D', 'L', 'Goals', '+/-', 'Pts']), header),
              ),
              for (final row in table.rows)
                Container(
                  color: row.isUs ? p.primary.container : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: cells(
                    columns([
                      '${row.rank}',
                      fmtRankChange(row.rankChange),
                      row.team,
                      '${row.played}',
                      '${row.won}',
                      '${row.drawn}',
                      '${row.lost}',
                      '${row.goalsFor}:${row.goalsAgainst}',
                      fmtGoalDifference(row.goalDifference),
                      '${row.points}',
                    ]),
                    row.isUs ? body.copyWith(color: p.primary.onContainer, fontWeight: FontWeight.w700) : body,
                  ),
                ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

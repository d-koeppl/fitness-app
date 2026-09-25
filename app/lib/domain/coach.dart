// Pure logic for the coach tab — the port of fitness-dashboard's
// web/lib/coach.ts, with its tests. The chat picker's order, the workouts
// pinned to a chat, the one-line summary of what the chat can see, and the
// day's Gemini budget as a chip.
//
// The scope options come from the generated client rather than a list kept
// here in step with the server: the History choices are the schema's
// `CoachLookbackDays` enum, labelled by an exhaustive switch (a new choice
// does not compile until it has a label), and the include switches are
// checked against `IncludeFlags` by a test.

import 'package:fitness_api/fitness_api.dart';

import 'format.dart';

/// How many workouts one chat may pin. Mirrors COACH_MAX_ATTACHED_SESSIONS
/// in functions/api/config.py — the server refuses past it, and this is
/// only so the picker can say so before a round trip is spent.
const coachMaxAttached = 10;

/// How deep the attachment picker's list of sessions goes. Longer than the
/// Fitness tab's list, because "compare this week's run with the same one
/// last month" is exactly the question worth attaching two workouts for.
const coachAttachPickerLimit = 40;

/// The History a new chat starts at: the daily report's own window.
const coachDefaultLookback = CoachLookbackDays.number14;

// --- the chat picker ----------------------------------------------------------

/// Move a conversation to the front of the list, inserting it if it is new.
/// The server orders by use, so this mirrors what a refetch would return —
/// without spending one on every message.
List<ConversationOut> promote(List<ConversationOut> list, ConversationOut conv) => [
  conv,
  ...list.where((other) => other.id != conv.id),
];

List<ConversationOut> removeById(List<ConversationOut> list, int id) =>
    list.where((conv) => conv.id != id).toList();

/// What the picker button shows. A chat with no conversation behind it yet
/// is the one you are about to start: nothing has been said in it, so it
/// has no title.
String conversationLabel(ConversationOut? conv) {
  final title = conv?.title.trim() ?? '';
  return title.isEmpty ? 'New chat' : title;
}

// --- workouts attached to a chat (ADR-021) --------------------------------------
//
// The composer holds session ids, not sessions: that is what the server
// takes and what a reopened chat gives back.

/// Add or remove one workout, keeping the order they were attached in. The
/// prompt lists them in that order, so "compare the first with the second"
/// means the same to the model as on screen — which is why an attached id
/// is removed rather than moved to the front. Over the cap the list comes
/// back untouched.
List<String> toggleAttached(List<String> ids, String id, {int max = coachMaxAttached}) {
  if (ids.contains(id)) return ids.where((other) => other != id).toList();
  if (ids.length >= max) return ids;
  return [...ids, id];
}

/// What one attachment chip says. Falls back to the day in the id when the
/// session is not in the picker's list — a chat reopened months later pins
/// a workout far past the newest few the picker holds, and the server still
/// resolves it. `match#<ref>` carries no day, so it reads "Workout".
String attachedLabel(String id, ExerciseSessionOut? session) {
  final day = session?.date ?? DateTime.tryParse(id.split('#').first);
  final name = session != null ? sessionTitle(session) : 'Workout';
  return day != null ? '$name · ${fmtDate(day)}' : name;
}

// --- what the chat is answered from ---------------------------------------------

/// The "include" switches, in the order they are offered.
enum IncludeKey {
  health('Health'),
  exercises('Workouts'),
  matches('Matches'),
  events('Calendar'),
  report('AI report'),
  alcohol('Beers');

  const IncludeKey(this.label);
  final String label;
}

/// Every switch on — what a new chat starts with.
final IncludeFlags includeAll = IncludeFlags(
  health: true,
  exercises: true,
  matches: true,
  events: true,
  report: true,
  alcohol: true,
);

/// Whether a switch is on. A flag the server left out defaults to on, as it
/// does there: a chat stored before the flag existed was answered with it.
bool isIncluded(IncludeFlags flags, IncludeKey key) =>
    switch (key) {
      IncludeKey.health => flags.health,
      IncludeKey.exercises => flags.exercises,
      IncludeKey.matches => flags.matches,
      IncludeKey.events => flags.events,
      IncludeKey.report => flags.report,
      IncludeKey.alcohol => flags.alcohol,
    } ??
    true;

/// The flags with one switch flipped.
IncludeFlags toggleInclude(IncludeFlags flags, IncludeKey key) {
  bool next(IncludeKey k) => k == key ? !isIncluded(flags, k) : isIncluded(flags, k);
  return IncludeFlags(
    health: next(IncludeKey.health),
    exercises: next(IncludeKey.exercises),
    matches: next(IncludeKey.matches),
    events: next(IncludeKey.events),
    report: next(IncludeKey.report),
    alcohol: next(IncludeKey.alcohol),
  );
}

int includedCount(IncludeFlags flags) => IncludeKey.values.where((k) => isIncluded(flags, k)).length;

/// The History choices, in order, without the generator's "unknown" case.
final List<CoachLookbackDays> lookbackOptions = CoachLookbackDays.values
    .where((d) => d != CoachLookbackDays.unknownDefaultOpenApi)
    .toList();

/// The long and short labels of one History choice.
({String label, String short}) lookbackLabels(CoachLookbackDays days) => switch (days) {
  CoachLookbackDays.number14 => (label: '14 days', short: '14d'),
  CoachLookbackDays.number30 => (label: '30 days', short: '30d'),
  CoachLookbackDays.number90 => (label: '90 days', short: '90d'),
  CoachLookbackDays.number182 => (label: '6 months', short: '6mo'),
  CoachLookbackDays.number365 => (label: '1 year', short: '1y'),
  CoachLookbackDays.number730 => (label: '2 years', short: '2y'),
  // A value this build does not know yet still renders as itself.
  CoachLookbackDays.unknownDefaultOpenApi => (label: 'Custom', short: '?'),
};

String lookbackLabel(CoachLookbackDays days) => lookbackLabels(days).label;

String attachedCountLabel(int count) => '$count workout${count == 1 ? '' : 's'}';

/// How many source names the closed line spells out before it counts. Two
/// is what fits beside the lookback and the workouts on a phone.
const _scopeNamesShown = 2;

/// The closed scope bar's one line: what is on, how far back, and how many
/// workouts ride along in full. Named rather than counted — "5 of 6" says a
/// switch is off without saying which, and sends you into the panel to find
/// out.
String scopeSummary(IncludeFlags include, CoachLookbackDays lookback, int attachedCount) {
  final on = [
    for (final key in IncludeKey.values)
      if (isIncluded(include, key)) key.label,
  ];
  final sources = on.isEmpty
      ? 'Nothing included'
      : on.length <= _scopeNamesShown
      ? on.join(', ')
      : '${on.take(_scopeNamesShown).join(', ')} +${on.length - _scopeNamesShown}';
  return [sources, lookbackLabel(lookback), if (attachedCount > 0) attachedCountLabel(attachedCount)].join(' · ');
}

// --- the day's Gemini budget ----------------------------------------------------

/// Where the budget stops being background information: roughly a fifth of
/// a default day, which still leaves room to finish a line of questioning
/// after the chip has changed colour.
const coachBudgetLow = 8;

enum BudgetTone { calm, low, spent }

/// The budget as one small chip plus the line behind it (ADR-013): legible
/// at a glance, coloured only as the day runs out, and the rest — requests
/// spent, which model is answering, when it turns over — in the detail.
({String label, BudgetTone tone, String detail}) budgetChip(CoachUsageOut usage) {
  final left = usage.chatRemaining;
  // Once the primary model's own allowance is spent, replies come from the
  // fallback's separate one — a different model answering, worth naming.
  final onFallback = usage.models.length > 1 && usage.models[0].used >= usage.models[0].limit;
  final fallback = onFallback ? ' · on ${usage.models[1].model}' : '';
  final resets = fmtTime(usage.resetsAt);
  final spent = '${usage.used}/${usage.limit} requests used';

  if (left <= 0) {
    return (
      label: 'None left',
      tone: BudgetTone.spent,
      detail: '$spent. The rest of today is held for the daily report — back at $resets.',
    );
  }
  return (
    label: '$left left',
    tone: left <= coachBudgetLow ? BudgetTone.low : BudgetTone.calm,
    detail: '$spent today · $left coach message${left == 1 ? '' : 's'} left$fallback · resets $resets',
  );
}

// Ported from fitness-dashboard's web/lib/coach.test.ts, case for case, plus
// the checks that tie the scope options to the generated client.
import 'package:fitness/domain/coach.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'format_test.dart' show exercise;

ConversationOut conv(int id, [String? title]) => ConversationOut(
  id: id,
  title: title ?? 'chat $id',
  createdAt: DateTime.utc(2026, 8, 31, 9),
  updatedAt: DateTime.utc(2026, 8, 31, 9),
  messageCount: 2,
);

IncludeFlags include({
  bool health = false,
  bool exercises = false,
  bool matches = false,
  bool events = false,
  bool report = false,
  bool alcohol = false,
}) => IncludeFlags(
  health: health,
  exercises: exercises,
  matches: matches,
  events: events,
  report: report,
  alcohol: alcohol,
);

CoachUsageOut usage({int used = 3, int limit = 40, int chatRemaining = 37, List<ModelUsageOut>? models}) =>
    CoachUsageOut(
      used: used,
      limit: limit,
      chatRemaining: chatRemaining,
      resetsAt: DateTime.utc(2026, 9, 11, 7),
      models: models ?? [ModelUsageOut(model: 'gemini-3.6-flash', used: 3, limit: 20)],
    );

void main() {
  group('promote', () {
    test('moves a chat to the front when it is used again', () {
      expect(promote([conv(1), conv(2), conv(3)], conv(3)).map((c) => c.id), [3, 1, 2]);
    });

    test('inserts a chat that is not in the list yet', () {
      expect(promote([conv(1)], conv(9)).map((c) => c.id), [9, 1]);
    });

    test('does not duplicate the promoted chat', () {
      expect(promote([conv(1), conv(2)], conv(1)).where((c) => c.id == 1), hasLength(1));
    });

    test('takes the new copy of the row, not the stale one', () {
      expect(promote([conv(1, 'New chat')], conv(1, 'how am I doing?')).first.title, 'how am I doing?');
    });
  });

  group('removeById', () {
    test('drops just the deleted chat', () {
      expect(removeById([conv(1), conv(2)], 1).map((c) => c.id), [2]);
    });

    test('leaves the list alone when the id is not there', () {
      expect(removeById([conv(1)], 99), hasLength(1));
    });
  });

  group('conversationLabel', () {
    test('names an unsaved chat', () => expect(conversationLabel(null), 'New chat'));
    test('uses the stored title', () => expect(conversationLabel(conv(1, 'taper before Saturday')), 'taper before Saturday'));
    test('falls back when the title is blank', () => expect(conversationLabel(conv(1, '   ')), 'New chat'));
  });

  group('toggleAttached', () {
    test('adds a workout at the end, keeping the order they were attached in', () {
      expect(toggleAttached(['a'], 'b'), ['a', 'b']);
    });

    test('removes one that is already attached', () {
      expect(toggleAttached(['a', 'b', 'c'], 'b'), ['a', 'c']);
    });

    test('does not reorder on a re-tap — it detaches', () {
      expect(toggleAttached(['a', 'b'], 'a'), ['b']);
    });

    test('refuses to go over the cap', () {
      expect(toggleAttached(['a', 'b'], 'c', max: 2), ['a', 'b']);
    });

    test('still lets you detach when the list is full', () {
      expect(toggleAttached(['a', 'b'], 'b', max: 2), ['a']);
    });

    test('the default cap is the server\'s', () {
      final full = [for (var i = 0; i < coachMaxAttached; i++) '$i'];
      expect(toggleAttached(full, 'x'), full);
    });
  });

  group('attachedLabel', () {
    test('names the session and the day it happened', () {
      expect(attachedLabel('2026-08-20#0', exercise()), 'Running · Thu 20 Aug');
    });

    test('falls back to the day in the id when the session is not in the list', () {
      expect(attachedLabel('2026-03-12#1', null), 'Workout · Thu 12 Mar');
    });

    test('drops the day for an id that carries none', () {
      expect(attachedLabel('match#99182', null), 'Workout');
    });
  });

  group('include switches', () {
    test('are exactly the flags the server takes', () {
      // A switch the server added would otherwise never be offered, and one
      // it dropped would be sent and refused.
      expect(includeAll.toJson().keys.toSet(), {for (final key in IncludeKey.values) key.name});
    });

    test('a flag the server left out reads as on, as it does there', () {
      expect(isIncluded(IncludeFlags(), IncludeKey.alcohol), isTrue);
    });

    test('toggling flips one and keeps the rest', () {
      final next = toggleInclude(include(health: true), IncludeKey.matches);
      expect([for (final k in IncludeKey.values) isIncluded(next, k)], [true, false, true, false, false, false]);
    });
  });

  group('includedCount', () {
    test('counts nothing when everything is off', () => expect(includedCount(include()), 0));
    test('counts only what is switched on', () => expect(includedCount(include(health: true, matches: true)), 2));
    test('counts every switch offered', () => expect(includedCount(includeAll), IncludeKey.values.length));
  });

  group('lookbackLabel', () {
    test('uses the label the pills offer', () {
      expect(lookbackLabel(CoachLookbackDays.number14), '14 days');
      expect(lookbackLabel(CoachLookbackDays.number182), '6 months');
      expect(lookbackLabel(CoachLookbackDays.number730), '2 years');
    });

    test('offers every choice the server accepts, in order', () {
      expect(lookbackOptions.map((d) => d.value), ['14', '30', '90', '182', '365', '730']);
    });

    test('still renders a value this build does not know', () {
      // A chat stored by a newer server, read by an older app.
      expect(lookbackLabel(CoachLookbackDays.unknownDefaultOpenApi), 'Custom');
    });
  });

  group('attachedCountLabel', () {
    test('counts what is pinned', () {
      expect(attachedCountLabel(1), '1 workout');
      expect(attachedCountLabel(3), '3 workouts');
    });
  });

  group('scopeSummary', () {
    const d30 = CoachLookbackDays.number30;
    const d14 = CoachLookbackDays.number14;

    test('names what is on while the names still fit', () {
      expect(scopeSummary(include(health: true), d30, 0), 'Health · 30 days');
      expect(scopeSummary(include(health: true, exercises: true), d30, 0), 'Health, Workouts · 30 days');
    });

    test('counts the rest once it runs out of room', () {
      final on = include(health: true, exercises: true, matches: true, events: true);
      expect(scopeSummary(on, d14, 0), 'Health, Workouts +2 · 14 days');
    });

    test('names them in the order the switches are offered, not the order they were set', () {
      expect(scopeSummary(include(alcohol: true, health: true), d14, 0), 'Health, Beers · 14 days');
    });

    test('says so when nothing is included', () {
      expect(scopeSummary(include(), d14, 0), 'Nothing included · 14 days');
    });

    test('mentions attachments only when there are some', () {
      final on = include(health: true);
      expect(scopeSummary(on, d30, 0), 'Health · 30 days');
      expect(scopeSummary(on, d30, 1), 'Health · 30 days · 1 workout');
      expect(scopeSummary(on, d30, 2), 'Health · 30 days · 2 workouts');
    });
  });

  group('budgetChip', () {
    test('stays background information on a normal day', () {
      final chip = budgetChip(usage());
      expect(chip.tone, BudgetTone.calm);
      expect(chip.label, '37 left');
    });

    test('turns low at the threshold, not one past it', () {
      expect(budgetChip(usage(chatRemaining: coachBudgetLow + 1)).tone, BudgetTone.calm);
      expect(budgetChip(usage(chatRemaining: coachBudgetLow)).tone, BudgetTone.low);
    });

    test('reads as spent once the chat\'s share is gone', () {
      final chip = budgetChip(usage(chatRemaining: 0, used: 37));
      expect(chip.tone, BudgetTone.spent);
      expect(chip.label, 'None left');
      expect(chip.detail, contains('held for the daily report'));
    });

    test('treats a count below zero as spent rather than as a negative', () {
      expect(budgetChip(usage(chatRemaining: -2)).tone, BudgetTone.spent);
      expect(budgetChip(usage(chatRemaining: -2)).label, 'None left');
    });

    test('counts one remaining message in the singular', () {
      expect(budgetChip(usage(chatRemaining: 1)).detail, contains('1 coach message left'));
      expect(budgetChip(usage(chatRemaining: 2)).detail, contains('2 coach messages left'));
    });

    test('carries the day\'s requests against the limit', () {
      expect(budgetChip(usage(used: 12, limit: 40)).detail, contains('12/40 requests used'));
    });

    test('says nothing about a fallback while the primary has room', () {
      final chip = budgetChip(
        usage(
          models: [
            ModelUsageOut(model: 'gemini-3.6-flash', used: 3, limit: 20),
            ModelUsageOut(model: 'gemini-3.7-flash', used: 0, limit: 20),
          ],
        ),
      );
      expect(chip.detail, isNot(contains('gemini-3.7-flash')));
    });

    test('names the fallback once the primary\'s own allowance is spent', () {
      final chip = budgetChip(
        usage(
          chatRemaining: 17,
          models: [
            ModelUsageOut(model: 'gemini-3.6-flash', used: 20, limit: 20),
            ModelUsageOut(model: 'gemini-3.7-flash', used: 0, limit: 20),
          ],
        ),
      );
      expect(chip.detail, contains('on gemini-3.7-flash'));
    });
  });
}

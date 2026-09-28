// The coach tab against the fake API: resuming the last chat, a turn, the
// resend of a message whose reply was lost (ADR-035), a failure handing the
// text back, charts and math in a reply, and "Ask the coach" from a
// workout's sheet.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fitness/data/coach.dart';
import 'package:fitness/ui/charts/coach_chart.dart';
import 'package:fitness/ui/sheets/exercise_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, Object?> usageJson({int remaining = 37}) => {
  'used': 3,
  'limit': 40,
  'chat_remaining': remaining,
  'resets_at': '2026-09-26T07:00:00Z',
  'models': [
    {'model': 'gemini-flash-latest', 'used': 3, 'limit': 20},
  ],
};

Map<String, Object?> convJson(int id, String title, {int count = 2}) => {
  'id': id,
  'title': title,
  'created_at': '2026-09-24T18:00:00Z',
  'updated_at': '2026-09-24T18:05:00Z',
  'message_count': count,
};

Map<String, Object?> message(int id, String role, String content) => {
  'id': id,
  'role': role,
  'content': content,
  'created_at': '2026-09-24T18:05:00Z',
};

const allOn = {'health': true, 'exercises': true, 'matches': true, 'events': true, 'report': true, 'alcohol': true};

Map<String, Object?> coachFixtures({List<Object?>? messages}) => {
  ...fixtures(),
  '/coach/usage': usageJson(),
  '/coach/conversations': [convJson(7, 'taper before Saturday'), convJson(3, 'older chat')],
  '/coach/conversations/7': {
    ...convJson(7, 'taper before Saturday'),
    'include': {...allOn, 'alcohol': false},
    'lookback_days': 30,
    'session_ids': <String>[],
    'messages': messages ?? [message(1, 'user', 'Should I taper?'), message(2, 'assistant', 'Yes, **lightly**.')],
  },
};

Map<String, Object?> turn(String question, String reply, {int conversation = 7}) => {
  'conversation': convJson(conversation, 'taper before Saturday', count: 4),
  'message': message(10, 'user', question),
  'reply': message(11, 'assistant', reply),
  'usage': usageJson(remaining: 36),
};

final noWaiting = [coachRetryDelaysProvider.overrideWithValue(const [Duration.zero, Duration.zero, Duration.zero])];

Future<void> openCoach(WidgetTester tester) async {
  await tester.tap(find.text('Coach'));
  await tester.pumpAndSettle();
}

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Send'));
  await settleRequests(tester);
}

DioException dropped(RequestOptions request) =>
    DioException(requestOptions: request, type: DioExceptionType.connectionError);

DioException status(RequestOptions request, int code, String detail) => DioException(
  requestOptions: request,
  response: Response(requestOptions: request, statusCode: code, data: {'detail': detail}),
  type: DioExceptionType.badResponse,
);

void main() {
  scrollTests();
  testWidgets('opening the coach resumes the last chat, held at its own settings', (tester) async {
    await pumpDashboard(tester, fakeApi(coachFixtures()));
    await openCoach(tester);

    expect(find.text('taper before Saturday'), findsOneWidget);
    expect(find.text('Should I taper?'), findsOneWidget);
    expect(find.textContaining('lightly', findRichText: true), findsOneWidget);
    // The chat's own switches and History, not the defaults.
    expect(find.text('Health, Workouts +3 · 30 days'), findsOneWidget);
    expect(find.text('37 left'), findsOneWidget);
  });

  testWidgets('a message goes out with the chat, its settings and an id of its own', (tester) async {
    final sent = <Sent>[];
    final reply = Completer<Object?>();
    await pumpDashboard(
      tester,
      fakeApi({...coachFixtures(), 'POST /coach/chat': (RequestOptions _) => reply.future}, sent: sent),
    );
    await openCoach(tester);

    await ask(tester, 'And on Friday?');
    // The question shows at once, with the coach thinking under it.
    expect(find.text('And on Friday?'), findsOneWidget);
    expect(find.text('Thinking…'), findsOneWidget);

    final body = sent.lastWhere((r) => r.path == '/coach/chat').body! as Map<String, Object?>;
    expect(body['content'], 'And on Friday?');
    expect(body['conversation_id'], 7);
    expect(body['lookback_days'], 30);
    expect(body['include'], {...allOn, 'alcohol': false});
    expect(body['session_ids'], <String>[]);
    expect(body['client_message_id'], matches(RegExp(r'^[0-9a-f]{32}$')));

    reply.complete(turn('And on Friday?', 'Rest on Friday.'));
    await tester.pumpAndSettle();
    expect(find.text('Thinking…'), findsNothing);
    expect(find.textContaining('Rest on Friday.', findRichText: true), findsOneWidget);
    expect(find.text('36 left'), findsOneWidget);
  });

  testWidgets('a reply lost on the way back is asked for again under the same id', (tester) async {
    final sent = <Sent>[];
    var calls = 0;
    await pumpDashboard(
      tester,
      fakeApi({
        ...coachFixtures(),
        'POST /coach/chat': (RequestOptions request) {
          calls++;
          // The connection drops; then the server is still answering the
          // first copy; then the stored reply comes back.
          if (calls == 1) throw dropped(request);
          if (calls == 2) throw status(request, 409, 'This message is still being answered.');
          return turn('And on Friday?', 'Rest on Friday.');
        },
      }, sent: sent),
      overrides: noWaiting,
    );
    await openCoach(tester);

    await ask(tester, 'And on Friday?');
    await tester.pumpAndSettle();

    final ids = {
      for (final r in sent.where((r) => r.path == '/coach/chat')) (r.body! as Map<String, Object?>)['client_message_id'],
    };
    expect(calls, 3);
    expect(ids, hasLength(1));
    expect(find.textContaining('Rest on Friday.', findRichText: true), findsOneWidget);
    expect(find.text('And on Friday?'), findsOneWidget);
  });

  testWidgets('a refused message comes back to the composer with the reason', (tester) async {
    final sent = <Sent>[];
    await pumpDashboard(
      tester,
      fakeApi({
        ...coachFixtures(),
        'POST /coach/chat': (RequestOptions request) => throw status(request, 502, 'Gemini request failed: 503'),
      }, sent: sent),
      overrides: noWaiting,
    );
    await openCoach(tester);
    final usageReads = sent.where((r) => r.path == '/coach/usage').length;

    await ask(tester, 'And on Friday?');
    await tester.pumpAndSettle();

    // Not resent: a 502 is an answer, and the same request gets the same one.
    expect(sent.where((r) => r.path == '/coach/chat'), hasLength(1));
    expect(find.text('Gemini request failed: 503'), findsOneWidget);
    expect(find.text('Thinking…'), findsNothing);
    // Back in the box, not left in the transcript.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'And on Friday?');
    // The slot may have been spent: the count is read again.
    expect(sent.where((r) => r.path == '/coach/usage').length, usageReads + 1);
  });

  testWidgets('a reply draws its chart and its maths', (tester) async {
    const reply =
        'Your week:\n\n```chart\n{"type": "bar", "title": "AZM per day", "unit": "AZM", '
        '"x": ["Mon", "Tue", "Wed"], "series": [{"name": "AZM", "values": [12, null, 40]}]}\n```\n\n'
        r'Form is $F - A$.';
    await pumpDashboard(
      tester,
      fakeApi(
        coachFixtures(messages: [message(1, 'user', 'My week?'), message(2, 'assistant', reply)]),
      ),
    );
    await openCoach(tester);

    expect(find.byType(CoachChartView), findsOneWidget);
    expect(find.text('AZM per day'), findsOneWidget);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('a chart the coach got wrong shows its source and why', (tester) async {
    const reply = '```chart\n{"type": "line", "x": ["a", "b"], "series": [{"values": [1]}]}\n```';
    await pumpDashboard(
      tester,
      fakeApi(coachFixtures(messages: [message(1, 'user', 'Chart?'), message(2, 'assistant', reply)])),
    );
    await openCoach(tester);

    expect(find.text('Could not draw this chart: Series 1 has 1 values for 2 labels'), findsOneWidget);
    expect(find.textContaining('"series"'), findsOneWidget);
  });

  testWidgets('"Ask the coach" on a workout pins it to the chat and opens the tab', (tester) async {
    final session = {
      'id': '2026-09-24#0',
      'date': '2026-09-24',
      'start_ts': '2026-09-24T18:00:00+02:00',
      'end_ts': '2026-09-24T19:00:00+02:00',
      'exercise_type': 'RUNNING',
      'duration_minutes': 60,
      'active_zone_minutes': 40,
      'average_heart_rate': 150,
      'metrics': <String, Object>{},
      'source': 'tracked',
      'ref_id': null,
      'title': null,
      'estimated_load': null,
      'skipped': false,
    };
    final sent = <Sent>[];
    await pumpDashboard(
      tester,
      fakeApi({
        ...coachFixtures(),
        '/health-data/exercises': [session],
        '/health-data/exercises/2026-09-24%230/heart-rate': null,
        'POST /coach/chat': (RequestOptions _) => turn('How was it?', 'Steady.'),
      }, sent: sent),
    );
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Fitness')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running').first);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetail), findsOneWidget);

    await tester.tap(find.text('Ask the coach about this session'));
    await tester.pumpAndSettle();

    // On the coach, in the chat it resumed, with the run added to its pins.
    expect(find.byType(ExerciseDetail), findsNothing);
    expect(find.text('Health, Workouts +3 · 30 days · 1 workout'), findsOneWidget);

    await ask(tester, 'How was it?');
    await tester.pumpAndSettle();
    final body = sent.lastWhere((r) => r.path == '/coach/chat').body! as Map<String, Object?>;
    expect(body['session_ids'], ['2026-09-24#0']);
  });
}

void scrollTests() {
  testWidgets('sending from further up the chat brings the view back down', (tester) async {
    final long = [for (var i = 0; i < 30; i++) message(i, i.isEven ? 'user' : 'assistant', 'Turn $i with some text.')];
    final reply = Completer<Object?>();
    await pumpDashboard(
      tester,
      fakeApi({...coachFixtures(messages: long), 'POST /coach/chat': (RequestOptions _) => reply.future}),
    );
    await openCoach(tester);
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(list).position;
    expect(position.pixels, greaterThan(0));

    await ask(tester, 'Back down?');
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(find.text('Thinking…'), findsOneWidget);
    reply.complete(turn('Back down?', 'Yes.'));
    await tester.pumpAndSettle();
  });
}

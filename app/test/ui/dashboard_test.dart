// The dashboard against a fake API: canned JSON per path, answered by a
// Dio interceptor, so the generated client, the Riverpod state and the
// widgets are all exercised without a network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  testWidgets('Today shows the tiles and the report from the API', (tester) async {
    await pumpDashboard(tester, fakeApi(fixtures()));

    expect(find.text('55 bpm'), findsOneWidget);
    expect(find.text('Resting HR · ↑1'), findsOneWidget);
    expect(find.text('59 ms'), findsOneWidget);
    expect(find.text('Variability · ↓22'), findsOneWidget);
    expect(find.text('6 h 53 m'), findsOneWidget);
    // Not weighed today: yesterday's weight, with its date.
    expect(find.text('79.1 kg'), findsOneWidget);
    expect(find.text('Weight · 24 Sept'), findsOneWidget);
    expect(find.text('988'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1 L'), findsOneWidget);

    expect(find.text('HRV rebounded strongly'), findsOneWidget);
    expect(find.text('Moderate Readiness'), findsOneWidget);
    expect(find.text('Keep tonight light.'), findsOneWidget);
    // The report can be selected and copied, as on the web.
    final headline = find.text('HRV rebounded strongly');
    expect(find.ancestor(of: headline, matching: find.byType(SelectionArea)), findsOneWidget);
  });

  testWidgets('Fitness shows the training status and the matches', (tester) async {
    await pumpDashboard(tester, fakeApi(fixtures()));
    await tester.tap(find.text('Fitness').last);
    await tester.pumpAndSettle();

    expect(find.text('Productive'), findsOneWidget);
    expect(find.text('54.9'), findsOneWidget);
    expect(find.text('71.2'), findsOneWidget);
    expect(find.text('-16'), findsOneWidget);
    expect(find.text('-30% of fitness'), findsOneWidget);
    expect(find.text('54/100'), findsOneWidget);

    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();
    expect(find.text('vs Kirchberg / D.'), findsOneWidget);
    expect(find.text('1W 0D 0L'), findsOneWidget);
  });

  testWidgets('a match opens the session it was, with the ÖFB report beside the watch', (tester) async {
    final match = {...(fixtures()['/matches']! as List).single as Map<String, Object?>, 'session_id': '2026-09-20#0'};
    final sent = <Sent>[];
    await pumpDashboard(
      tester,
      fakeApi({
        ...fixtures(),
        '/matches': [match],
        // Not in the dashboard's list, so the sheet asks for it by id —
        // escaped, as the trace is.
        '/health-data/exercises/2026-09-20%230': {
          'id': '2026-09-20#0',
          'date': '2026-09-20',
          'start_ts': '2026-09-20T13:22:00Z',
          'end_ts': '2026-09-20T15:44:00Z',
          'exercise_type': 'SOCCER',
          'title': null,
          'duration_minutes': 142,
          'active_zone_minutes': 249,
          'average_heart_rate': 153,
          'estimated_load': null,
          'metrics': <String, Object>{},
          'source': 'tracked',
          'ref_id': null,
          'skipped': false,
          'match': match,
        },
        '/health-data/exercises/2026-09-20%230/heart-rate': null,
      }, sent: sent),
    );
    await tester.tap(find.text('Fitness').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('vs Kirchberg / D.'));
    await tester.pumpAndSettle();

    expect(sent.where((r) => r.path == '/health-data/exercises/2026-09-20%230'), hasLength(1));
    // Titled as the match, not "Soccer", with the scoreline and the watch's
    // numbers on one sheet.
    expect(find.text('Soccer'), findsNothing);
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('3:0'), findsOneWidget);
    expect(find.text('249.0'), findsWidgets);
    expect(find.text('153'), findsOneWidget);
  });

  testWidgets('Health features the first metric and lists the rest', (tester) async {
    await pumpDashboard(tester, fakeApi(fixtures()));
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();

    expect(find.text('Key metrics'), findsOneWidget);
    expect(find.text('7-day avg 55 bpm'), findsOneWidget);
    expect(find.text('Heart rate variability'), findsWidgets);
  });

  testWidgets('one failing source leaves the others on screen', (tester) async {
    final responses = fixtures()..remove('/training/status');
    await pumpDashboard(tester, fakeApi(responses));

    expect(find.text('55 bpm'), findsOneWidget);
    await tester.tap(find.text('Fitness').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load training status'), findsOneWidget);
  });

  testWidgets('no report yet is not an error', (tester) async {
    final responses = fixtures()..remove('/reports/latest');
    await pumpDashboard(tester, fakeApi(responses));

    expect(find.textContaining('No report yet'), findsOneWidget);
    expect(find.textContaining('Could not load the latest report'), findsNothing);
  });

  testWidgets('an account the API refuses is told so and offered sign-out', (tester) async {
    await pumpDashboard(tester, fakeApi(fixtures(), status: 403));

    expect(find.text('owner@example.com is not allowed.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('a rejected session asks to sign in again', (tester) async {
    await pumpDashboard(tester, fakeApi(fixtures(), status: 401));

    expect(find.text('Your session was not accepted. Sign in again.'), findsOneWidget);
  });
}

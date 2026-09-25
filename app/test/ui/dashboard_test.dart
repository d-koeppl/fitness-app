// The dashboard against a fake API: canned JSON per path, answered by a
// Dio interceptor, so the generated client, the Riverpod state and the
// widgets are all exercised without a network.
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

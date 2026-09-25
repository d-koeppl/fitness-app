// The dashboard against a fake API: canned JSON per path, answered by a
// Dio interceptor, so the generated client, the Riverpod state and the
// widgets are all exercised without a network.
import 'package:dio/dio.dart';
import 'package:fitness/data/dashboard.dart';
import 'package:fitness/ui/shell.dart';
import 'package:fitness/ui/theme/palette.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _day(String date, {int? rhr, num? hrv, int? sleep, int? steps, num? weight}) => {
      'date': date,
      'steps': steps,
      'resting_hr': rhr,
      'hrv_ms': hrv,
      'sleep_minutes': sleep,
      'active_zone_minutes': null,
      'weight_kg': weight,
      'vo2max': null,
    };

/// A day like 2026-09-25 on production, trimmed.
Map<String, Object?> fixtures() => {
      '/matches': [
        {
          'id': 1,
          'oefb_game_id': '1',
          'match_date': '2026-09-20',
          'opponent': 'Kirchberg / D.',
          'home_away': 'home',
          'result': '3:0',
          'started': true,
          'minutes_played': 90,
          'goals': 1,
          'yellow_card': false,
          'red_card': false,
        },
      ],
      '/matches/missing': null,
      '/calendar/events': <Object>[],
      '/oauth/google/status': {
        'calendar': {'connected': true, 'scopes': null, 'access_token_expires_at': null, 'updated_at': null},
        'health': {'connected': true, 'scopes': null, 'access_token_expires_at': null, 'updated_at': null},
      },
      // Newest first, as the API sends it.
      '/health-data/daily': [
        _day('2026-09-25', rhr: 55, hrv: 58.95, sleep: 413, steps: 988),
        _day('2026-09-24', rhr: 54, hrv: 80.7, sleep: 398, steps: 11204, weight: 79.1),
      ],
      '/health-data/latest': {
        'weight_kg': {'value': 79.1, 'date': '2026-09-24'},
        'vo2max': null,
      },
      '/health-data/exercises': <Object>[],
      '/reports/latest': {
        'id': 45,
        'created_at': '2026-09-25T05:52:00Z',
        'trigger': 'manual_refresh',
        'period_start': null,
        'period_end': null,
        'model': 'gemini',
        'prompt_version': 'v1',
        'tokens_used': null,
        'summary_md': '## HRV rebounded strongly\n\nBuilding on **yesterday**.',
        'insights': {
          'readiness': 'moderate',
          'recommendations': ['Keep tonight light.'],
        },
      },
      '/training/status': {
        'status': 'productive',
        'headline': "A productive block — you're banking fatigue to build fitness.",
        'fitness': 54.9,
        'fatigue': 71.2,
        'form': -16.3,
        'form_pct': -29.7,
        'ramp_pct': 7.2,
        'recovery': 54,
        'recovery_parts': {'hrv': 45, 'resting_hr': 46, 'sleep': 86},
        'readiness': 64,
        'readiness_parts': <String, Object>{},
        'days_of_history': 296,
        'series': [
          {'date': '2026-09-23', 'load': 17, 'fitness': 54.0, 'fatigue': 70.0},
          {'date': '2026-09-24', 'load': 96, 'fitness': 54.9, 'fatigue': 71.2},
        ],
        'scores': [
          {'date': '2026-09-25', 'recovery': 54, 'readiness': 64},
        ],
        'notes': ['Today (2026-09-25) is still in progress — load is measured through yesterday.'],
      },
      '/drinks': {
        'count': 2,
        'volume_l': 0.5,
        'alcohol_grams': 40,
        'first_logged_at': null,
        'last_logged_at': null,
      },
    };

/// A client whose every request is answered from [responses] (status 200),
/// or with [status] for all of them when it is set.
FitnessApi fakeApi(Map<String, Object?> responses, {int? status}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  final api = FitnessApi(dio: dio, interceptors: []);
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    if (status != null) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: status, data: {'detail': 'nope'}),
        type: DioExceptionType.badResponse,
      ));
      return;
    }
    if (!responses.containsKey(options.path)) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      ));
      return;
    }
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: responses[options.path]));
  }));
  return api;
}

Future<void> pumpDashboard(WidgetTester tester, FitnessApi api) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: buildTheme(Palette.light, Brightness.light),
      home: DashboardShell(email: 'owner@example.com', signOut: () async {}),
    ),
  ));
  await tester.pumpAndSettle();
}

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

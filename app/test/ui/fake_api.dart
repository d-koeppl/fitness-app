// A fake API for the widget tests: canned JSON per path, answered by a Dio
// interceptor, so the generated client, the Riverpod state and the widgets
// are all exercised without a network.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fitness/data/dashboard.dart';
import 'package:fitness/data/push.dart';
import 'package:fitness/push/push_service.dart';
import 'package:fitness/ui/shell.dart';
import 'package:fitness/ui/theme/palette.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

/// An opponent's standing next to ours, as the API sends it.
Map<String, Object?> standing({
  int rank = 3,
  int points = 15,
  int? gap = 4,
  String? strength = 'stronger',
  String tableDay = '2026-09-25',
  bool atKickoff = true,
}) => {
  'rank': rank,
  'rank_change': 0,
  'played': 7,
  'points': points,
  'points_per_game': points / 7,
  'goal_difference': 0,
  'our_rank': 8,
  'our_points': 11,
  'our_points_per_game': 1.57,
  'points_gap': gap,
  'strength': strength,
  'table_day': tableDay,
  'at_kickoff': atKickoff,
};

Map<String, Object?> _row(
  int rank,
  String team,
  int points, {
  int gf = 0,
  int ga = 0,
  int change = 0,
  bool us = false,
}) => {
  'rank': rank,
  'rank_change': change,
  'team': team,
  'is_us': us,
  'played': 7,
  'won': 0,
  'drawn': 0,
  'lost': 0,
  'goals_for': gf,
  'goals_against': ga,
  'goal_difference': gf - ga,
  'points': points,
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
      'session_id': null,
      'opponent_standing': standing(rank: 10, points: 9, gap: -2, strength: 'level', tableDay: '2026-09-19'),
    },
  ],
  '/matches/missing': null,
  '/league/table': {
    'league': '2. Nordwest',
    'day': '2026-09-25',
    'fetched_at': '2026-09-25T01:30:00Z',
    'rows': [
      _row(1, 'Ottensheim', 17, gf: 25, ga: 6, change: 1),
      _row(3, 'Sarleinsbach', 15, gf: 29, ga: 11, change: -2),
      _row(8, 'Eidenberg/Geng', 11, gf: 12, ga: 10, change: -2, us: true),
    ],
  },
  '/league/fixtures': [
    {
      'oefb_game_id': '4120032',
      'kickoff': '2026-10-04T14:00:00Z',
      'opponent': 'Sarleinsbach',
      'home_away': 'away',
      'art': 'Liga',
      'opponent_standing': standing(),
    },
  ],
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
  '/drinks': {'count': 2, 'volume_l': 0.5, 'alcohol_grams': 40, 'first_logged_at': null, 'last_logged_at': null},
};

/// A request the fake answered, for a test to assert on.
typedef Sent = ({String method, String path, Object? body});

/// A request's JSON body, decoded: the generated client sends it encoded.
Object? bodyOf(RequestOptions request) {
  final data = request.data;
  return data is String && data.isNotEmpty ? jsonDecode(data) : data;
}

/// Let a tap's request travel through Dio to the fake, and its answer back.
/// Dio runs its interceptors on a zero-length timer, which a bare `pump()`
/// does not fire (it only flushes microtasks), so time is advanced by zero.
Future<void> settleRequests(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(Duration.zero);
  }
}

/// Answers one request, possibly later: a test that needs replies to land
/// out of order returns a Future it completes itself.
typedef Answer = FutureOr<Object?> Function(RequestOptions request);

/// A client whose requests are answered from [responses] (status 200), by
/// "METHOD /path" first and then by "/path" whatever the method; with
/// [status] set, every request fails with it. A value that is an [Answer]
/// is called; any other is the JSON body. Every request lands in [sent].
FitnessApi fakeApi(Map<String, Object?> responses, {int? status, List<Sent>? sent}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  final api = FitnessApi(dio: dio, interceptors: []);

  void fail(RequestOptions options, RequestInterceptorHandler handler, int code, [Object? data]) => handler.reject(
    DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: code, data: data),
      type: DioExceptionType.badResponse,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        sent?.add((method: options.method, path: options.path, body: bodyOf(options)));
        if (status != null) return fail(options, handler, status, {'detail': 'nope'});
        final key = '${options.method} ${options.path}';
        final hit = responses.containsKey(key) ? key : (responses.containsKey(options.path) ? options.path : null);
        if (hit == null) return fail(options, handler, 404);
        final value = responses[hit];
        try {
          final data = value is Answer ? await value(options) : value;
          handler.resolve(Response(requestOptions: options, statusCode: 200, data: data));
        } on DioException catch (error) {
          handler.reject(error);
        }
      },
    ),
  );
  return api;
}

/// The dashboard shell on a phone-sized screen, signed in, against [api];
/// with [push], on a device that has push (by default it has none), and
/// any further provider [overrides].
Future<void> pumpDashboard(
  WidgetTester tester,
  FitnessApi api, {
  PushService? push,
  Future<void> Function()? signOut,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(api), pushServiceProvider.overrideWithValue(push), ...overrides],
      child: MaterialApp(
        theme: buildTheme(Palette.light, Brightness.light),
        home: DashboardShell(email: 'owner@example.com', signOut: signOut ?? () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

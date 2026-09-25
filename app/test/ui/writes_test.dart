// The dashboard's writes and sheets against the fake API: the beer
// stepper's in-flight rule, New report's two halves, a metric sheet, a
// skipped session and a corrected earlier day.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fitness/domain/series.dart';
import 'package:fitness/ui/sheets/detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, Object?> counter(int count) => {
  'count': count,
  'volume_l': 0.5,
  'alcohol_grams': 20 * count,
  'first_logged_at': null,
  'last_logged_at': null,
};

String iso(DateTime day) => dayKey(day);

final today = startOfDay(DateTime.now());
final yesterday = addDays(today, -1);

/// The open sheet's own list — the shell's scrollables are still under it.
Finder get sheetList => find.descendant(of: find.byType(DetailSheet), matching: find.byType(Scrollable)).first;

/// The beer tile's count, which sits in its round disc.
Finder beerCount(String count) =>
    find.descendant(of: find.byTooltip('$count beers. Type a different number'), matching: find.text(count));

void main() {
  testWidgets('a beer tap moves the tile at once, and a late earlier reply does not roll it back', (tester) async {
    final replies = <Completer<Object?>>[];
    final sent = <Sent>[];
    final api = fakeApi({
      ...fixtures(),
      'POST /drinks': (RequestOptions _) {
        final reply = Completer<Object?>();
        replies.add(reply);
        return reply.future;
      },
    }, sent: sent);
    await pumpDashboard(tester, api);
    expect(beerCount('2'), findsOneWidget);

    await tester.tap(find.byTooltip('One more beer'));
    await tester.tap(find.byTooltip('One more beer'));
    await settleRequests(tester);
    // Both taps show before either reply is back.
    expect(beerCount('4'), findsOneWidget);
    expect(sent.where((r) => r.method == 'POST' && r.path == '/drinks'), hasLength(2));

    // The first reply lands while the second is still out: it may not
    // replace the number.
    replies[0].complete(counter(3));
    await settleRequests(tester);
    expect(beerCount('4'), findsOneWidget);

    replies[1].complete(counter(4));
    await tester.pumpAndSettle();
    expect(beerCount('4'), findsOneWidget);
  });

  testWidgets('a failed tap takes back its own step and says why', (tester) async {
    final api = fakeApi({
      ...fixtures(),
      'POST /drinks': (RequestOptions request) => throw DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 500, data: {'detail': 'Firestore is down'}),
        type: DioExceptionType.badResponse,
      ),
    });
    await pumpDashboard(tester, api);

    await tester.tap(find.byTooltip('One more beer'));
    await tester.pumpAndSettle();

    expect(beerCount('2'), findsOneWidget);
    expect(find.text('Firestore is down'), findsOneWidget);
  });

  testWidgets('New report syncs, then analyses, then shows the report it made', (tester) async {
    final sync = Completer<Object?>();
    final generate = Completer<Object?>();
    final sent = <Sent>[];
    // Once generated, the new report is also the latest one the re-read gets.
    var latest = fixtures()['/reports/latest']! as Map<String, Object?>;
    final api = fakeApi({
      ...fixtures(),
      '/reports/latest': (RequestOptions _) => latest,
      'POST /sync': (RequestOptions _) => sync.future,
      'POST /reports/generate': (RequestOptions _) =>
          generate.future.then((report) => latest = report! as Map<String, Object?>),
    }, sent: sent);
    await pumpDashboard(tester, api);

    await tester.tap(find.text('New report'));
    await settleRequests(tester);
    expect(find.text('Syncing…'), findsOneWidget);

    sync.complete({
      'sources': {'health': 'ok', 'heart_rate': 'ok', 'calendar': 'ok'},
    });
    await settleRequests(tester);
    expect(find.text('Analyzing…'), findsOneWidget);

    generate.complete({...latest, 'id': 46, 'trigger': 'manual', 'summary_md': '## Fresh legs\n\nA quiet night.'});
    await tester.pumpAndSettle();

    expect(find.text('Fresh legs'), findsOneWidget);
    expect(find.text('New report'), findsOneWidget);
    final posts = [
      for (final r in sent)
        if (r.method == 'POST') r.path,
    ];
    expect(posts, ['/sync', '/reports/generate']);
  });

  testWidgets('a tile opens its metric sheet, with every day in the list', (tester) async {
    final api = fakeApi({
      ...fixtures(),
      '/health-data/daily': [
        {..._daily(today), 'resting_hr': 55},
        {..._daily(yesterday), 'resting_hr': 52},
      ],
    });
    await pumpDashboard(tester, api);

    await tester.tap(find.text('55 bpm'));
    await tester.pumpAndSettle();

    expect(find.text('Resting heart rate'), findsOneWidget);
    expect(find.text('Daily values'), findsOneWidget);
    // The week's average of the two days, over the chart.
    expect(find.text('54 bpm'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Yesterday'), 200, scrollable: sheetList);
    expect(find.text('52 bpm'), findsOneWidget);

    // Another period is another set of buckets, not another request.
    await tester.tap(find.text('Y'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly averages'), findsOneWidget);
  });

  testWidgets('a match nobody tracked can be marked skipped, and the sheet follows', (tester) async {
    var skipped = false;
    final sent = <Sent>[];
    Map<String, Object?> match() => {
      'id': 'match-1',
      'date': iso(yesterday),
      'start_ts': null,
      'end_ts': null,
      'exercise_type': null,
      'title': 'vs Kirchberg / D.',
      'duration_minutes': 90,
      'active_zone_minutes': null,
      'average_heart_rate': null,
      'estimated_load': 96,
      'metrics': <String, Object>{},
      'source': 'match',
      'ref_id': '1',
      'skipped': skipped,
    };
    final api = fakeApi({
      ...fixtures(),
      '/health-data/exercises': (RequestOptions _) => [match()],
      'POST /training/skips': (RequestOptions request) {
        skipped = (bodyOf(request)! as Map)['skipped'] as bool;
        return {'source': 'match', 'ref_id': '1', 'skipped': skipped};
      },
    }, sent: sent);
    await pumpDashboard(tester, api);
    await tester.tap(find.text('Fitness').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('vs Kirchberg / D.'));
    await tester.pumpAndSettle();
    expect(find.text('Not tracked'), findsOneWidget);

    await tester.tap(find.text('Mark as skipped'));
    await tester.pumpAndSettle();

    final skip = sent.singleWhere((r) => r.path == '/training/skips');
    expect(skip.body, {'source': 'match', 'ref_id': '1', 'skipped': true});
    // After the re-read the sheet shows the session as the API now has it.
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Count it again'), findsOneWidget);
  });

  testWidgets("a tracked session's trace is asked for with its id escaped", (tester) async {
    final sent = <Sent>[];
    final id = '${iso(yesterday)}#0';
    final api = fakeApi({
      ...fixtures(),
      '/health-data/exercises': [
        {
          'id': id,
          'date': iso(yesterday),
          'start_ts': '${iso(yesterday)}T15:00:00Z',
          'end_ts': '${iso(yesterday)}T16:00:00Z',
          'exercise_type': 'RUNNING',
          'title': null,
          'duration_minutes': 60,
          'active_zone_minutes': 55,
          'average_heart_rate': 148,
          'estimated_load': null,
          'metrics': <String, Object>{},
          'source': 'tracked',
          'ref_id': null,
          'skipped': false,
        },
      ],
      // "#" unescaped would start a URL fragment and cut the path at the day.
      '/health-data/exercises/${iso(yesterday)}%230/heart-rate': {
        'session_id': id,
        'date': iso(yesterday),
        'start_ts': '${iso(yesterday)}T15:00:00Z',
        'end_ts': '${iso(yesterday)}T16:00:00Z',
        'fetched_at': '${iso(today)}T02:00:00Z',
        'samples': [
          [0, 95],
          [1800, 150],
          [3600, 120],
        ],
        'sample_count': 3,
        'min_bpm': 95,
        'max_bpm': 150,
        'average_bpm': 128,
        'zones': <Object>[],
        'zone_source': null,
        'resting_hr': 56,
        'max_hr': null,
      },
    }, sent: sent);
    await pumpDashboard(tester, api);
    await tester.tap(find.text('Fitness').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();

    expect(sent.where((r) => r.path.endsWith('/heart-rate')).single.path, contains('%230'));
    expect(find.text('95–150 bpm'), findsOneWidget);
  });

  testWidgets('the beer sheet corrects an earlier day, but not below what a report counted', (tester) async {
    final sent = <Sent>[];
    final api = fakeApi({
      ...fixtures(),
      '/drinks/days': [
        {'date': iso(today), 'count': 2, 'reported': 0, 'editable': false},
        {'date': iso(yesterday), 'count': 1, 'reported': 1, 'editable': true},
        {'date': iso(addDays(today, -2)), 'count': 0, 'reported': 0, 'editable': true},
      ],
      'PUT /drinks/days/${yesterday.toString()}': (RequestOptions request) => {
        'date': iso(yesterday),
        'count': (bodyOf(request)! as Map)['count'],
        'reported': 1,
        'editable': true,
      },
    }, sent: sent);
    await pumpDashboard(tester, api);

    await tester.tap(find.text('Beer'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in any day'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Today · on the counter'), 200, scrollable: sheetList);

    // A report already counted yesterday's one, so the minus is off.
    final fewer = find.byTooltip('One fewer beer on Yesterday — not possible, a report already counted these');
    expect(tester.widget<IconButton>(find.ancestor(of: fewer, matching: find.byType(IconButton))).onPressed, isNull);

    await tester.tap(find.byTooltip('One more beer on Yesterday'));
    await tester.pumpAndSettle();

    final put = sent.singleWhere((r) => r.method == 'PUT');
    expect(put.body, {'count': 2});
    expect(find.byTooltip('One fewer beer on Yesterday'), findsOneWidget);
  });
}

Map<String, Object?> _daily(DateTime day) => {
  'date': iso(day),
  'steps': null,
  'resting_hr': null,
  'hrv_ms': null,
  'sleep_minutes': null,
  'active_zone_minutes': null,
  'weight_kg': null,
  'vo2max': null,
};

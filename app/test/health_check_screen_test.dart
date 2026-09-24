import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness/ui/health_check_screen.dart';

Widget _screen(Future<String> Function() checkStatus) => MaterialApp(
      home: HealthCheckScreen(checkStatus: checkStatus, apiBaseUrl: 'https://api.test'),
    );

void main() {
  testWidgets('shows the status the API reports', (tester) async {
    await tester.pumpWidget(_screen(() async => 'ok'));
    await tester.pumpAndSettle();

    expect(find.text('API status: ok'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('shows a checking state while the request is in flight', (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(_screen(() => pending.future));

    expect(find.text('Checking…'), findsOneWidget);
    pending.complete('ok');
  });

  testWidgets('offers a retry when the API is unreachable, and it works', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_screen(() async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return 'ok';
    }));
    await tester.pumpAndSettle();

    expect(find.text('API unreachable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('API status: ok'), findsOneWidget);
    expect(calls, 2);
  });
}

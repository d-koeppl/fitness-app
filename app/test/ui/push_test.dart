// The report push on the app's side (ADR-030), with FCM stood in for:
// the header's bell, registering the token, a push arriving or tapped, and
// sign-out dropping the device.
import 'dart:async';

import 'package:fitness/push/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

class FakePush implements PushService {
  FakePush({this.permissionNow = PushPermission.undecided, this.answer = PushPermission.granted});

  PushPermission permissionNow;

  /// What the permission prompt comes back with.
  PushPermission answer;
  String? currentToken = 'token-1';
  bool launched = false;
  int prompts = 0;
  int deletes = 0;

  final refreshes = StreamController<String>.broadcast();
  final arrivalsIn = StreamController<PushArrival>.broadcast();
  final tapsIn = StreamController<void>.broadcast();

  @override
  String get platform => 'android';

  @override
  Future<bool> supported() async => true;

  @override
  Future<PushPermission> permission() async => permissionNow;

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return permissionNow = answer;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Future<void> deleteToken() async => deletes++;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushArrival> get arrivals => arrivalsIn.stream;

  @override
  Stream<void> get taps => tapsIn.stream;

  @override
  Future<bool> launchedByTap() async => launched;
}

final registered = {'platform': 'android', 'registered_at': '2026-09-25T16:30:00Z'};

Iterable<Sent> requests(List<Sent> sent, String method, String path) =>
    sent.where((r) => r.method == method && r.path == path);

int selectedTab(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('the bell asks, registers the token, and goes away', (tester) async {
    final sent = <Sent>[];
    final push = FakePush();
    await pumpDashboard(tester, fakeApi({...fixtures(), 'PUT /push/devices': registered}, sent: sent), push: push);

    // Nothing is asked or sent until the bell is tapped.
    expect(push.prompts, 0);
    expect(requests(sent, 'PUT', '/push/devices'), isEmpty);

    await tester.tap(find.byTooltip('Turn on notifications'));
    await settleRequests(tester);
    await tester.pumpAndSettle();

    expect(push.prompts, 1);
    expect(requests(sent, 'PUT', '/push/devices').single.body, {'token': 'token-1', 'platform': 'android'});
    expect(find.byTooltip('Turn on notifications'), findsNothing);
  });

  testWidgets('with permission already given, the token is registered at start without asking', (tester) async {
    final sent = <Sent>[];
    final push = FakePush(permissionNow: PushPermission.granted);
    await pumpDashboard(tester, fakeApi({...fixtures(), 'PUT /push/devices': registered}, sent: sent), push: push);

    expect(push.prompts, 0);
    expect(requests(sent, 'PUT', '/push/devices'), hasLength(1));
    expect(find.byTooltip('Turn on notifications'), findsNothing);

    // FCM rotated the token: the server gets the new one.
    push.refreshes.add('token-2');
    await settleRequests(tester);
    expect(requests(sent, 'PUT', '/push/devices').last.body, {'token': 'token-2', 'platform': 'android'});
  });

  testWidgets('blocked notifications point to the settings and send nothing', (tester) async {
    final sent = <Sent>[];
    final push = FakePush(permissionNow: PushPermission.denied);
    await pumpDashboard(tester, fakeApi(fixtures(), sent: sent), push: push);

    // A token left from before the block is dropped, so the server prunes it.
    expect(push.deletes, 1);

    await tester.tap(find.byTooltip('Notifications are blocked'));
    await tester.pump();

    expect(find.textContaining('Allow them in the system or browser settings'), findsOneWidget);
    expect(push.prompts, 0);
    expect(requests(sent, 'PUT', '/push/devices'), isEmpty);
  });

  testWidgets('a failed registration says so and keeps the bell', (tester) async {
    final push = FakePush();
    final api = fakeApi({...fixtures(), 'PUT /push/devices': (_) => throw StateError('unreachable')});
    await pumpDashboard(tester, api, push: push);

    await tester.tap(find.byTooltip('Turn on notifications'));
    await settleRequests(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not turn on notifications'), findsOneWidget);
    expect(find.byTooltip('Turn on notifications'), findsOneWidget);
  });

  testWidgets('a tapped push opens Today and re-reads the report', (tester) async {
    final sent = <Sent>[];
    final push = FakePush(permissionNow: PushPermission.granted);
    await pumpDashboard(tester, fakeApi({...fixtures(), 'PUT /push/devices': registered}, sent: sent), push: push);

    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 2);
    final reads = requests(sent, 'GET', '/reports/latest').length;

    push.tapsIn.add(null);
    await settleRequests(tester);
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(requests(sent, 'GET', '/reports/latest').length, reads + 1);
  });

  testWidgets('a push that arrives with the app in front shows a snackbar', (tester) async {
    final sent = <Sent>[];
    final push = FakePush(permissionNow: PushPermission.granted);
    await pumpDashboard(tester, fakeApi({...fixtures(), 'PUT /push/devices': registered}, sent: sent), push: push);
    final reads = requests(sent, 'GET', '/reports/latest').length;

    push.arrivalsIn.add(PushArrival(title: 'Fitness report ready', body: 'Legs are fresh.'));
    await settleRequests(tester);
    await tester.pump();

    expect(find.text('Fitness report ready: Legs are fresh.'), findsOneWidget);
    expect(requests(sent, 'GET', '/reports/latest').length, reads + 1);
  });

  testWidgets('signing out drops this device first', (tester) async {
    final sent = <Sent>[];
    final push = FakePush(permissionNow: PushPermission.granted);
    var signedOut = false;
    await pumpDashboard(
      tester,
      fakeApi({...fixtures(), 'PUT /push/devices': registered, 'DELETE /push/devices': null}, sent: sent),
      push: push,
      signOut: () async {
        // By now the server has been told and the token is gone.
        expect(requests(sent, 'DELETE', '/push/devices').single.body, {'token': 'token-1'});
        expect(push.deletes, 1);
        signedOut = true;
      },
    );

    await tester.tap(find.byTooltip('owner@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await settleRequests(tester);
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });
}

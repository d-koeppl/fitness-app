import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The public half of the project's Web Push certificate (Firebase console,
/// Cloud Messaging). Public by design: the browser hands it to its push
/// service to prove messages come from this project, and only Google holds
/// the private half (ADR-030).
const _webVapidKey = 'BArrLY4Ww0KHKwLuA5SHiCM-aeyMUFKXg38FnZYldPx5qe3LgjY4liJN9h9KzwuYJ_JI0A-4Fdbup0-fXCcbwvs';

enum PushPermission {
  granted,

  /// Refused, in a way only the system or browser settings can undo.
  denied,

  /// Never asked, so a tap can still ask.
  undecided,
}

/// A push that arrived while the app was in front, where the system shows
/// nothing by itself.
class PushArrival {
  PushArrival({required this.title, required this.body});

  final String title;
  final String body;
}

/// What the app needs from FCM, so widgets and tests do not touch Firebase
/// directly (as AuthService does for sign-in).
abstract class PushService {
  /// "android" or "web", as the API stores it.
  String get platform;

  /// False in a browser without the Push API (Safari outside an installed
  /// app, private windows in some browsers).
  Future<bool> supported();

  Future<PushPermission> permission();

  /// Asks, with the system's or browser's own prompt.
  Future<PushPermission> requestPermission();

  Future<String?> token();

  /// Invalidates the token at FCM, so the server's next send to it comes
  /// back "unregistered" and prunes it there too.
  Future<void> deleteToken();

  Stream<String> get tokenRefreshes;

  Stream<PushArrival> get arrivals;

  /// A tap on a push brought the app to the front.
  Stream<void> get taps;

  /// Whether a tap on a push is what started the app.
  Future<bool> launchedByTap();
}

class FirebasePushService implements PushService {
  FirebasePushService(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  String get platform => kIsWeb ? 'web' : 'android';

  @override
  Future<bool> supported() => _messaging.isSupported();

  @override
  Future<PushPermission> permission() async => _permission(await _messaging.getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async => _permission(await _messaging.requestPermission());

  PushPermission _permission(NotificationSettings settings) => switch (settings.authorizationStatus) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.deniedPermanently => PushPermission.denied,
    // A browser never asks twice; Android 13+ may ask once more.
    AuthorizationStatus.denied => kIsWeb ? PushPermission.denied : PushPermission.undecided,
    AuthorizationStatus.notDetermined => PushPermission.undecided,
  };

  @override
  Future<String?> token() => _messaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushArrival> get arrivals => FirebaseMessaging.onMessage.map(
    (message) => PushArrival(title: message.notification?.title ?? '', body: message.notification?.body ?? ''),
  );

  @override
  Stream<void> get taps => FirebaseMessaging.onMessageOpenedApp.map((_) {});

  @override
  Future<bool> launchedByTap() async => await _messaging.getInitialMessage() != null;
}

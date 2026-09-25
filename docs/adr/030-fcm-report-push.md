# ADR-030 — The report push through Firebase Cloud Messaging

**Status:** Accepted · **Date:** 2026-09-25
**Supersedes:** in fitness-dashboard, [ADR-005](https://github.com/d-koeppl/fitness-dashboard/blob/main/docs/adr/005-web-push.md) (Web Push with VAPID)

Numbered 030 because the port plan reserved it for FCM (see ADR-031).
Written in phase 6.

## Context

fitness-dashboard sent Web Push itself: a VAPID key pair in its `.env`,
browser subscriptions in Postgres, `pywebpush` to send. It pushed twice:
"Fitness report ready" after the automatic report, and a test push from a
button. Route C ([ADR-028](028-route-c-firebase.md)) adds a native Android
app, and Web Push cannot reach one.

## Decision

- **FCM, for Android and the browser build.** One API and one token
  format for both. The functions send with firebase-admin as their own
  service account, so there is no server key or VAPID private key to keep
  in Secret Manager. The browser needs the Web Push certificate's *public*
  key, which is compiled into the app (`lib/push/push_service.dart`).
- **No iOS yet.** It needs an Apple Developer account, an APNs key in
  Firebase, and a Mac to build on. On iOS the app has no push and shows
  no bell.
- **One push:** "Fitness report ready", with the report's
  `readiness_reason` as its text, after the automatic evening report
  (`run_daily_fallback`, ADR-033). New report still sends none, because
  whoever tapped it is watching the screen. The test-push button is gone:
  a real report is the test.
- **Devices are `push_devices` documents,** keyed by a SHA-256 of the
  token (a token is ~160 characters of FCM's choosing, and an id may not
  contain `/`). `PUT /push/devices` registers one and is idempotent;
  `DELETE /push/devices` removes one. There is no send endpoint.
- **A token FCM calls unregistered or foreign is deleted** when a send
  reports it, as the old sender pruned a 410. Other failures leave the
  device in place, since they may pass.
- **The app keeps the server's copy current.** When notifications are
  allowed, it registers its token at every start and on every FCM
  rotation. When they are not, it deletes its token at FCM, so the
  server's next send prunes it. Sign-out unregisters the device and
  deletes the token before signing out. It gives up after 5 s so sign-out
  still works offline, and the deleted token is pruned later anyway.
- **The bell.** As in the web app, a bell in the header shows until
  notifications are on. A tap asks for permission (Android 13+ and
  browsers need an explicit grant). Once they are blocked, only the system
  or browser settings can undo that, and the bell says so.
- **Opening the report.** A tap on the push switches to Today and re-reads
  the latest report. A push that arrives with the app in front shows a
  snackbar, because the system shows nothing then. In a browser a click
  only focuses the tab and the page hears nothing of it, so returning to
  the app with notifications on re-reads the report (one request).
- **A failed push never fails the report.** The report is already saved,
  and the job's log line says what the push did:
  `ok (report N; push: sent 1, pruned 0, failed 0)`.

## Consequences

- ✅ No push secrets, and one sender for both platforms.
- ✅ A notification on Android without a server the phone must reach.
- ⚠️ The web build needs `firebase-messaging-sw.js` at the site root, with
  the Firebase JS SDK version that `firebase_core_web` loads. The two are
  bumped together.
- ⚠️ Android shows the push on FCM's default "Miscellaneous" channel.
  A named channel would need native code to create it. That can wait until
  there is a second kind of push.
- ⚠️ Nothing is pushed on a day when New report ran first, because the
  fallback only reports on a day without a report. This is as before.

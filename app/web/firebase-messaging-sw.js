// FCM's service worker for the browser build (ADR-030). The Firebase SDK
// registers this file by name when the app asks for a push token, and it
// shows the report push while no tab of the app is in front. A click opens
// or focuses the app at the link the server sends (WEB_APP_URL).
//
// The SDK version matches the one firebase_core_web loads for the page
// (supportedFirebaseJsSdkVersion); bump both together. The config is the
// web app's from lib/firebase_options.dart, and public.
importScripts("https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyB_FucEYww1KUdLvSXhLwJez5_KKgOSKKg",
  appId: "1:1026765822354:web:cc391707109a9e971d494b",
  messagingSenderId: "1026765822354",
  projectId: "fitness-75c22",
  authDomain: "fitness-75c22.firebaseapp.com",
  storageBucket: "fitness-75c22.firebasestorage.app",
});

firebase.messaging();

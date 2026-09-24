/// Where the `api` Cloud Function lives.
///
/// Override per run with `--dart-define=API_BASE_URL=...`, e.g. the local
/// emulator: http://127.0.0.1:5001/fitness-75c22/europe-west1/api
/// (Android emulators reach the host PC as 10.0.2.2 instead of 127.0.0.1).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://europe-west1-fitness-75c22.cloudfunctions.net/api',
);

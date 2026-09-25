/// Where the `api` Cloud Function lives.
///
/// Override per run with `--dart-define=API_BASE_URL=...`, e.g. the local
/// emulator: http://127.0.0.1:5001/fitness-75c22/europe-west1/api
/// (Android emulators reach the host PC as 10.0.2.2 instead of 127.0.0.1).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://europe-west1-fitness-75c22.cloudfunctions.net/api',
);

/// Host of the Firebase Auth emulator, e.g. `127.0.0.1` (or `10.0.2.2`
/// from an Android emulator). Empty — the default — signs in for real.
/// Pass `--dart-define=AUTH_EMULATOR_HOST=127.0.0.1` together with an
/// emulator API_BASE_URL: the local API only trusts emulator tokens.
const String authEmulatorHost = String.fromEnvironment('AUTH_EMULATOR_HOST');

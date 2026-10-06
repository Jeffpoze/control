# Contributing

Control is a Flutter app for iOS and Android. See the README for features and layout.

- State lives in `provider` ChangeNotifiers in `lib/state/`. There's no router package: tabs go through `NavState` and an `IndexedStack`, and other screens are pushed with `Navigator`.
- Every service client extends `ServiceClient` (`lib/services/service_client.dart`). Keep response parsing in static methods so it can be unit-tested with `MockClient`, and add a test in `test/services_test.dart` for any new client or API change.
- Secrets (API keys, passwords, custom headers) go through `SecretStore`, which uses the iOS Keychain and Android's encrypted storage. Never put them in SharedPreferences.
- Don't add App Transport Security exceptions, cleartext-traffic exceptions or certificate bypasses. `dart:io` HTTP isn't subject to them, so plain-HTTP servers on the home network already work.
- Before committing, run `dart format lib test`, `flutter analyze` (no issues) and `flutter test`. CI runs the same checks and builds both apps.

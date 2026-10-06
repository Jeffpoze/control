import 'package:control/app.dart';
import 'package:control/models/server.dart';
import 'package:control/state/nav_state.dart';
import 'package:control/state/server_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch shows the welcome and all tabs', (tester) async {
    final store = ServerStore(secrets: MemorySecretStore());
    await store.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider(create: (_) => NavState()),
        ],
        child: const ControlApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to Control'), findsOneWidget);
    for (final tab in ['Home', 'Downloads', 'Media', 'Calendar', 'More']) {
      expect(find.text(tab), findsWidgets);
    }

    await tester.tap(find.text('Downloads').last);
    await tester.pump();
    expect(find.text('No download clients yet'), findsOneWidget);
  });

  test('servers round-trip, with secrets kept out of preferences', () async {
    final secrets = MemorySecretStore();
    final store = ServerStore(secrets: secrets);
    await store.load();
    await store.save(
      ServerConfig(
        id: 'a',
        kind: ServiceKind.sonarr,
        name: 'Sonarr',
        localUrl: '10.0.0.2:8989',
        apiKey: 'secret-key',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('servers.v1'), isNot(contains('secret-key')));
    expect(secrets.values['server.a'], contains('secret-key'));

    final reloaded = ServerStore(secrets: secrets);
    await reloaded.load();
    expect(reloaded.servers.single.apiKey, 'secret-key');
    expect(
      reloaded.servers.single.baseUris.single.toString(),
      'http://10.0.0.2:8989',
    );

    await reloaded.remove('a');
    expect(secrets.values, isEmpty);
  });
}

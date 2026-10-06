import 'package:control/models/server.dart';
import 'package:control/services/arr.dart';
import 'package:control/services/overseerr.dart';
import 'package:control/widgets/discover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trending banner shows titles and swipes', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TrendingBanner(
                items: [
                  DiscoverResult({
                    'id': 1,
                    'mediaType': 'movie',
                    'title': 'First Film',
                    'releaseDate': '2026-01-01',
                    'voteAverage': 8.1,
                  }),
                  DiscoverResult({
                    'id': 2,
                    'mediaType': 'tv',
                    'name': 'Second Show',
                  }),
                ],
                onTap: (r) => tapped.add(r.title),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('First Film'), findsOneWidget);
    expect(find.text('#1 TRENDING · MOVIE'), findsOneWidget);
    expect(find.text('★ 8.1'), findsOneWidget);

    await tester.tap(find.text('First Film'));
    expect(tapped, ['First Film']);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second Show'), findsOneWidget);
  });

  testWidgets('now downloading strip shows progress and time left', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowDownloadingStrip(
            items: [
              ActiveDownload(
                kind: ServiceKind.sonarr,
                serverId: 's',
                title: 'Severance',
                subtitle: 'S02E01 · Hello',
                progress: 0.42,
                status: 'downloading',
                timeLeft: const Duration(minutes: 7),
              ),
              ActiveDownload(
                kind: ServiceKind.radarr,
                serverId: 'r',
                title: 'Dune',
                status: 'delay',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('42% · 7m left'), findsOneWidget);
    expect(find.text('Waiting (delay profile)'), findsOneWidget);
  });
}

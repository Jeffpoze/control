import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:control/models/server.dart';
import 'package:control/services/arr.dart';
import 'package:control/services/bazarr.dart';
import 'package:control/services/comicarr.dart';
import 'package:control/services/download_client.dart';
import 'package:control/services/media_server.dart';
import 'package:control/services/ntfy.dart';
import 'package:control/services/nzbget.dart';
import 'package:control/services/overseerr.dart';
import 'package:control/services/qbittorrent.dart';
import 'package:control/services/sabnzbd.dart';
import 'package:control/services/service_client.dart';
import 'package:control/services/tautulli.dart';
import 'package:control/services/tmdb.dart';
import 'package:control/services/tracearr.dart';
import 'package:control/services/transmission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ServerConfig server(
  ServiceKind kind, {
  String local = '192.168.1.10:8080',
  String remote = '',
  String apiKey = 'KEY',
  String user = '',
  String pass = '',
}) => ServerConfig(
  id: 'x',
  kind: kind,
  name: kind.label,
  localUrl: local,
  remoteUrl: remote,
  apiKey: apiKey,
  username: user,
  password: pass,
);

http.Response json(
  Object body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

void main() {
  group('addresses', () {
    test('normalizeUrl adds a scheme and drops trailing slashes', () {
      expect(normalizeUrl('10.0.0.2:8989').toString(), 'http://10.0.0.2:8989');
      expect(
        normalizeUrl('https://x.example.com/sonarr/').toString(),
        'https://x.example.com/sonarr',
      );
    });

    test('joinUri keeps the URL base and encodes spaces as %20', () {
      final uri = joinUri(
        Uri.parse('http://nas:5055/requests'),
        '/api/v1/search',
        {'query': 'the office', 'n': 'a+b'},
      );
      expect(uri.path, '/requests/api/v1/search');
      expect(uri.query, 'query=the%20office&n=a%2Bb');
    });

    test('joinUri repeats list values', () {
      final uri = joinUri(Uri.parse('http://p:9696'), '/api/v1/search', {
        'indexerIds': ['1', '2'],
      });
      expect(uri.query, 'indexerIds=1&indexerIds=2');
    });

    test('falls back to the away address and remembers it', () async {
      final hosts = <String>[];
      final mock = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == '192.168.1.10') {
          throw const SocketException('unreachable');
        }
        return json({'version': '4.0'});
      });
      final client = ArrClient(
        server(ServiceKind.sonarr, remote: 'https://sonarr.example.com'),
        httpClient: mock,
      );
      await client.test();
      await client.test();
      expect(hosts, [
        '192.168.1.10',
        'sonarr.example.com',
        'sonarr.example.com',
      ]);
      expect(client.activeBase.toString(), 'https://sonarr.example.com');
    });

    test('a 401 explains the API key', () async {
      final client = ArrClient(
        server(ServiceKind.radarr),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );
      expect(
        client.test(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('API key'),
          ),
        ),
      );
    });
  });

  group('SABnzbd', () {
    test('parses the queue and gives the speed to the first active slot', () {
      final snap = SabnzbdClient.parseQueue({
        'queue': {
          'paused': false,
          'kbpersec': '2048',
          'mbleft': '1500',
          'diskspace1': '100',
          'slots': [
            {
              'nzo_id': 'a',
              'filename': 'Show.S01E01',
              'status': 'Downloading',
              'mb': '1000',
              'mbleft': '250',
              'percentage': '75',
              'timeleft': '0:02:05',
              'cat': 'tv',
            },
            {
              'nzo_id': 'b',
              'filename': 'Movie',
              'status': 'Queued',
              'mb': '2000',
              'mbleft': '2000',
              'percentage': '0',
              'timeleft': '0:00:00',
              'cat': '*',
            },
          ],
        },
      });
      expect(snap.downSpeed, 2048 * 1024);
      expect(snap.items.first.state, DownloadState.downloading);
      expect(snap.items.first.progress, 0.75);
      expect(snap.items.first.eta, const Duration(minutes: 2, seconds: 5));
      expect(snap.items.first.downSpeed, 2048 * 1024);
      expect(snap.items[1].state, DownloadState.queued);
      expect(snap.items[1].downSpeed, 0);
      expect(snap.items[1].category, isNull);
    });

    test('sends the API key and reports a bad one', () async {
      late Uri seen;
      final client = SabnzbdClient(
        server(ServiceKind.sabnzbd),
        httpClient: MockClient((req) async {
          seen = req.url;
          return json({'status': false, 'error': 'API Key Incorrect'});
        }),
      );
      await expectLater(
        client.pauseAll(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'm',
            contains('API key'),
          ),
        ),
      );
      expect(seen.queryParameters['apikey'], 'KEY');
      expect(seen.queryParameters['mode'], 'pause');
    });
  });

  group('NZBGet', () {
    test('parses groups', () {
      final snap = NzbgetClient.parse(
        {
          'DownloadRate': 1048576,
          'DownloadPaused': false,
          'RemainingSizeMB': 300,
        },
        [
          {
            'NZBID': 7,
            'NZBName': 'Thing',
            'Status': 'DOWNLOADING',
            'FileSizeMB': 400,
            'RemainingSizeMB': 300,
            'PausedSizeMB': 0,
            'Category': '',
          },
        ],
      );
      final item = snap.items.single;
      expect(item.id, '7');
      expect(item.progress, 0.25);
      expect(item.eta, const Duration(seconds: 300));
      expect(item.category, isNull);
    });

    test('uses JSON-RPC with basic auth', () async {
      late http.Request seen;
      final client = NzbgetClient(
        server(ServiceKind.nzbget, user: 'nzbget', pass: 'tegbzn'),
        httpClient: MockClient((req) async {
          seen = req;
          return json({'result': true});
        }),
      );
      await client.pauseAll();
      expect(seen.url.path, '/jsonrpc');
      expect(jsonDecode(seen.body)['method'], 'pausedownload');
      expect(seen.headers['Authorization'], basicAuth('nzbget', 'tegbzn'));
    });
  });

  group('qBittorrent', () {
    test(
      'logs in, then falls back from stop to pause on older versions',
      () async {
        final paths = <String>[];
        final mock = MockClient((req) async {
          paths.add(req.url.path);
          switch (req.url.path) {
            case '/api/v2/auth/login':
              return http.Response(
                'Ok.',
                200,
                headers: {'set-cookie': 'SID=abc; HttpOnly; path=/'},
              );
            case '/api/v2/torrents/stop':
              return http.Response('', 404);
            default:
              expect(req.headers['Cookie'], 'SID=abc');
              return http.Response('', 200);
          }
        });
        final client = QbittorrentClient(
          server(ServiceKind.qbittorrent, user: 'admin', pass: 'pw'),
          httpClient: mock,
        );
        await client.pauseAll();
        await client.pauseAll();
        expect(paths, [
          '/api/v2/auth/login',
          '/api/v2/torrents/stop',
          '/api/v2/torrents/pause',
          '/api/v2/torrents/pause',
        ]);
      },
    );

    test('maps states', () {
      expect(QbittorrentClient.stateOf('stalledUP'), DownloadState.seeding);
      expect(QbittorrentClient.stateOf('stoppedDL'), DownloadState.paused);
      expect(QbittorrentClient.stateOf('pausedUP'), DownloadState.completed);
      final t = QbittorrentClient.parseTorrent({
        'hash': 'h',
        'name': 'n',
        'state': 'downloading',
        'progress': 0.5,
        'size': 100,
        'amount_left': 50,
        'eta': 8640000,
      });
      expect(t.eta, isNull);
    });
  });

  group('Transmission', () {
    test('does the session id handshake', () async {
      var calls = 0;
      final client = TransmissionClient(
        server(ServiceKind.transmission, local: 'nas:9091'),
        httpClient: MockClient((req) async {
          calls++;
          expect(req.url.path, '/transmission/rpc');
          if (req.headers['X-Transmission-Session-Id'] != 'sid1') {
            return http.Response(
              '',
              409,
              headers: {'x-transmission-session-id': 'sid1'},
            );
          }
          return json({'result': 'success', 'arguments': {}});
        }),
      );
      await client.pauseAll();
      await client.resumeAll();
      expect(calls, 3);
    });

    test('maps statuses', () {
      final t = TransmissionClient.parseTorrent({
        'id': 3,
        'name': 'n',
        'status': 6,
        'percentDone': 1,
        'error': 0,
        'eta': -1,
      });
      expect(t.state, DownloadState.seeding);
      expect(t.id, '00000003');
    });
  });

  group('Sonarr/Radarr/Lidarr', () {
    test('Sonarr add body', () {
      final c = ArrClient(server(ServiceKind.sonarr));
      final item = c.toMedia({
        'title': 'Severance',
        'tvdbId': 371980,
        'images': [],
      });
      final body = c.addBody(
        item,
        qualityProfileId: 4,
        rootFolderPath: '/tv',
        languageProfileId: 1,
        monitor: 'future',
      );
      expect(body['tvdbId'], 371980);
      expect(body['qualityProfileId'], 4);
      expect(body['languageProfileId'], 1);
      expect(body['monitored'], true);
      expect(body['addOptions'], {
        'monitor': 'future',
        'searchForMissingEpisodes': true,
        'searchForCutoffUnmetEpisodes': false,
      });
    });

    test('Radarr calendar picks releases inside the window', () async {
      final c = ArrClient(
        server(ServiceKind.radarr),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v3/calendar');
          expect(req.headers['X-Api-Key'], 'KEY');
          return json([
            {
              'title': 'Film',
              'inCinemas': '2026-01-01T00:00:00Z',
              'digitalRelease': '2026-10-10T00:00:00Z',
              'hasFile': false,
              'images': [
                {
                  'coverType': 'poster',
                  'url': '/MediaCover/1/poster.jpg?lastWrite=1',
                },
              ],
            },
          ]);
        }),
      );
      final entries = await c.calendar(
        DateTime.utc(2026, 10, 5),
        DateTime.utc(2026, 10, 19),
      );
      expect(entries.single.subtitle, 'Digital release');
      expect(
        entries.single.posterUrl,
        'http://192.168.1.10:8080/MediaCover/1/poster.jpg?lastWrite=1&apikey=KEY',
      );
    });

    test('Lidarr uses API v1', () async {
      final c = ArrClient(
        server(ServiceKind.lidarr),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v1/artist');
          return json([
            {
              'id': 2,
              'artistName': 'Björk',
              'monitored': true,
              'statistics': {'trackFileCount': 3, 'totalTrackCount': 10},
            },
            {'id': 1, 'artistName': 'ABBA', 'monitored': true},
          ]);
        }),
      );
      final items = await c.library();
      expect(items.map((i) => i.title), ['ABBA', 'Björk']);
      expect(items[1].haveCount, 3);
      expect(items[1].totalCount, 10);
    });

    test('season pack folds into one active download', () async {
      final c = ArrClient(
        server(ServiceKind.sonarr),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v3/queue');
          expect(req.url.queryParameters['includeSeries'], 'true');
          Map<String, dynamic> record(int id, int ep, String dl) => {
            'id': id,
            'downloadId': dl,
            'title': 'Show.S02.1080p.WEB-DL',
            'status': dl == 'A' ? 'downloading' : 'queued',
            'size': 1000,
            'sizeleft': dl == 'A' ? 250 : 1000,
            'timeleft': '1.02:03:04',
            'series': {
              'title': 'Severance',
              'images': [
                {'coverType': 'poster', 'remoteUrl': 'https://img/p.jpg'},
                {'coverType': 'fanart', 'remoteUrl': 'https://img/f.jpg'},
              ],
            },
            'episode': {
              'seasonNumber': 2,
              'episodeNumber': ep,
              'title': 'Episode $ep',
            },
          };
          return json({
            'records': [
              record(3, 5, 'B'),
              record(1, 1, 'A'),
              record(2, 2, 'A'),
            ],
          });
        }),
      );
      final active = await c.activeDownloads();
      expect(active, hasLength(2));
      final pack = active.first;
      expect(pack.isDownloading, isTrue);
      expect(pack.title, 'Severance');
      expect(pack.subtitle, 'Season 2 · 2 episodes');
      expect(pack.progress, 0.75);
      expect(pack.posterUrl, 'https://img/p.jpg');
      expect(pack.fanartUrl, 'https://img/f.jpg');
      expect(
        pack.timeLeft,
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
      );
      expect(active.last.subtitle, 'S02E05 · Episode 5');
      expect(active.last.status, 'queued');
    });

    test('Radarr active download shows the year', () {
      final c = ArrClient(server(ServiceKind.radarr));
      final active = c.toActive([
        ArrQueueItem({
          'id': 1,
          'title': 'Dune.Part.Two.2024.2160p',
          'status': 'Downloading',
          'size': 100,
          'sizeleft': 0,
          'movie': {'title': 'Dune: Part Two', 'year': 2024},
        }),
      ]);
      expect(active.single.title, 'Dune: Part Two');
      expect(active.single.subtitle, '2024');
      expect(active.single.isDownloading, isTrue);
      expect(active.single.posterUrl, isNull);
    });

    test('time left parses .NET TimeSpans', () {
      expect(
        parseTimeSpan('00:12:05'),
        const Duration(minutes: 12, seconds: 5),
      );
      expect(parseTimeSpan(null), isNull);
      expect(parseTimeSpan('soon'), isNull);
    });
  });

  group('Overseerr', () {
    test('trending keeps movies and shows, drops people', () async {
      final c = OverseerrClient(
        server(ServiceKind.overseerr),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v1/discover/trending');
          expect(req.url.queryParameters['page'], '1');
          expect(req.headers['X-Api-Key'], 'KEY');
          return json({
            'page': 1,
            'results': [
              {
                'id': 1,
                'mediaType': 'movie',
                'title': 'Film',
                'releaseDate': '2026-09-01',
                'backdropPath': '/b.jpg',
                'posterPath': '/p.jpg',
                'voteAverage': 7.84,
              },
              {'id': 2, 'mediaType': 'person', 'name': 'Someone'},
              {
                'id': 3,
                'mediaType': 'tv',
                'name': 'Show',
                'firstAirDate': '2025-01-01',
                'mediaInfo': {'status': 5},
              },
            ],
          });
        }),
      );
      final items = await c.discover(DiscoverFeed.trending);
      expect(items.map((i) => i.title), ['Film', 'Show']);
      final film = items.first;
      expect(film.backdropUrl, 'https://image.tmdb.org/t/p/w1280/b.jpg');
      expect(film.posterUrl, 'https://image.tmdb.org/t/p/w342/p.jpg');
      expect(film.rating, closeTo(7.84, 0.001));
      expect(film.year, 2026);
      expect(film.canRequest, isTrue);
      final show = items.last;
      expect(show.isTv, isTrue);
      expect(show.canRequest, isFalse);
      expect(show.availabilityLabel, 'Available');
    });

    test('single-kind feeds fill in a missing media type', () {
      final items = OverseerrClient.parseResults({
        'results': [
          {'id': 9, 'title': 'Upcoming'},
        ],
      }, mediaType: 'movie');
      expect(items.single.mediaType, 'movie');
      expect(OverseerrClient.parseResults(null), isEmpty);
      expect(DiscoverFeed.upcomingTv.path, '/api/v1/discover/tv/upcoming');
    });
  });

  group('Custom headers', () {
    test('lines parse, junk is skipped', () {
      expect(
        parseHeaderLines(
          'CF-Access-Client-Id: abc.access\n\nbad line\nX-Token:  a:b \n has space: x',
        ),
        {'CF-Access-Client-Id': 'abc.access', 'X-Token': 'a:b'},
      );
    });

    test('are sent with every request, after proxy auth', () async {
      final c = ArrClient(
        ServerConfig(
          id: 'h',
          kind: ServiceKind.sonarr,
          name: 'Sonarr',
          localUrl: 'sonarr.example.com',
          apiKey: 'KEY',
          customHeaders: 'CF-Access-Client-Id: id\nCF-Access-Client-Secret: s',
        ),
        httpClient: MockClient((req) async {
          expect(req.headers['CF-Access-Client-Id'], 'id');
          expect(req.headers['CF-Access-Client-Secret'], 's');
          expect(req.headers['X-Api-Key'], 'KEY');
          return json({'version': '4.0'});
        }),
      );
      await c.test();
    });

    test('are a secret, not a preference', () {
      final s = ServerConfig(
        id: 'h',
        kind: ServiceKind.radarr,
        name: 'Radarr',
        customHeaders: 'X-Secret: 1',
      );
      expect(s.toJson().toString(), isNot(contains('X-Secret')));
      expect(s.secretsJson()['customHeaders'], 'X-Secret: 1');
      expect(ServerConfig.fromJson(s.toJson(), s.secretsJson())!.headerMap, {
        'X-Secret': '1',
      });
    });
  });

  group('Emby/Jellyfin', () {
    final sessions = [
      {
        'Id': 'sess1',
        'UserName': 'jeff',
        'Client': 'Emby Web',
        'DeviceName': 'Chrome',
        'PlayState': {
          'PositionTicks': 3000,
          'IsPaused': true,
          'PlayMethod': 'Transcode',
        },
        'TranscodingInfo': {'Bitrate': 8000000},
        'NowPlayingItem': {
          'Id': 'ep1',
          'Type': 'Episode',
          'Name': 'Pilot',
          'SeriesName': 'Severance',
          'SeriesId': 'ser1',
          'SeriesPrimaryImageTag': 'tag1',
          'ParentIndexNumber': 1,
          'IndexNumber': 1,
          'RunTimeTicks': 12000,
        },
      },
      {'Id': 'idle', 'UserName': 'nobody'},
      {
        'Id': 'sess2',
        'UserName': 'guest',
        'PlayState': {'PlayMethod': 'DirectPlay'},
        'NowPlayingItem': {
          'Id': 'mov1',
          'Type': 'Movie',
          'Name': 'Dune',
          'ProductionYear': 2021,
          'ImageTags': {'Primary': 'tag2'},
        },
      },
    ];

    test('sessions parse; idle ones are dropped', () {
      final list = MediaServerClient.parseSessions(
        sessions,
        Uri.parse('http://10.0.0.5:8096'),
      );
      expect(list, hasLength(2));
      final ep = list.first;
      expect(ep.id, 'sess1');
      expect(ep.title, 'Severance');
      expect(ep.subtitle, 'S01E01 · Pilot');
      expect(ep.user, 'jeff');
      expect(ep.player, 'Emby Web · Chrome');
      expect(ep.progress, 0.25);
      expect(ep.state, 'paused');
      expect(ep.transcoding, isTrue);
      expect(ep.quality, '8.0 Mbps');
      expect(
        ep.thumbUrl,
        'http://10.0.0.5:8096/Items/ser1/Images/Primary?maxHeight=300&tag=tag1',
      );
      final movie = list.last;
      expect(movie.subtitle, '2021');
      expect(movie.transcoding, isFalse);
      expect(movie.thumbUrl, contains('/Items/mov1/Images/Primary'));
    });

    test('Emby uses X-Emby-Token, Jellyfin the Authorization header', () async {
      final emby = MediaServerClient(
        server(ServiceKind.emby),
        httpClient: MockClient((req) async {
          expect(req.headers['X-Emby-Token'], 'KEY');
          return json({'Version': '4.9'});
        }),
      );
      await emby.test();
      final jelly = MediaServerClient(
        server(ServiceKind.jellyfin),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/Sessions');
          expect(req.headers['Authorization'], 'MediaBrowser Token="KEY"');
          return json(sessions);
        }),
      );
      expect((await jelly.activity()).sessions, hasLength(2));
    });

    test('stop posts to the session', () async {
      final paths = <String>[];
      final c = MediaServerClient(
        server(ServiceKind.emby),
        httpClient: MockClient((req) async {
          paths.add('${req.method} ${req.url.path}');
          return http.Response('', 204);
        }),
      );
      await c.terminate(
        PlaySession(id: 'sess1', title: 'x'),
        message: 'Server maintenance',
      );
      expect(paths, [
        'POST /Sessions/sess1/Message',
        'POST /Sessions/sess1/Playing/Stop',
      ]);
    });
  });

  group('Tautulli', () {
    test('episode session', () {
      final s = TautulliClient.parseSession({
        'session_key': 42,
        'media_type': 'episode',
        'grandparent_title': 'Severance',
        'title': 'Pilot',
        'parent_media_index': '1',
        'media_index': '2',
        'friendly_name': 'Jeff',
        'player': 'Apple TV',
        'progress_percent': '50',
        'state': 'playing',
        'transcode_decision': 'transcode',
        'quality_profile': '1080p',
        'grandparent_thumb': '/library/1/thumb',
      }, (p) => 'img:$p');
      expect(s.id, '42');
      expect(s.title, 'Severance');
      expect(s.subtitle, 'S01E02 · Pilot');
      expect(s.progress, 0.5);
      expect(s.transcoding, isTrue);
      expect(s.thumbUrl, 'img:/library/1/thumb');
    });
  });

  group('Bazarr', () {
    test('wanted episodes and movies', () {
      final eps = BazarrClient.parseWanted({
        'data': [
          {
            'seriesTitle': 'Severance',
            'episode_number': '1x02',
            'episodeTitle': 'Half Loop',
            'sonarrSeriesId': 5,
            'sonarrEpisodeId': 77,
            'missing_subtitles': [
              {'name': 'French', 'code2': 'fr', 'hi': false, 'forced': false},
              {'name': 'English', 'code2': 'en', 'hi': true, 'forced': false},
              {'name': 'broken'},
            ],
          },
        ],
        'total': 1,
      }, movies: false);
      final w = eps.single;
      expect(w.title, 'Severance');
      expect(w.subtitle, '1x02 · Half Loop');
      expect(w.missing.map((l) => l.label), ['French', 'English · HI']);
      expect(w.episodeId, 77);

      final movies = BazarrClient.parseWanted({
        'data': [
          {
            'title': 'Dune',
            'radarrId': 9,
            'missing_subtitles': [
              {'name': 'French', 'code2': 'fr', 'forced': true},
            ],
          },
        ],
      }, movies: true);
      expect(movies.single.movieId, 9);
      expect(movies.single.missing.single.label, 'French · Forced');
    });

    test('history', () {
      final events = BazarrClient.parseHistory({
        'data': [
          {
            'seriesTitle': 'Severance',
            'episode_number': '1x02',
            'language': {'name': 'French', 'code2': 'fr'},
            'description': 'French subtitles downloaded from opensubtitles',
            'timestamp': '2 hours ago',
          },
        ],
      }, movies: false);
      expect(events.single.subtitle, '1x02 · French');
      expect(events.single.when, '2 hours ago');
    });

    test('search one language', () async {
      final c = BazarrClient(
        server(ServiceKind.bazarr),
        httpClient: MockClient((req) async {
          expect(req.method, 'PATCH');
          expect(req.url.path, '/api/episodes/subtitles');
          expect(req.headers['X-API-KEY'], 'KEY');
          expect(req.url.queryParameters, {
            'seriesid': '5',
            'episodeid': '77',
            'language': 'en',
            'hi': 'true',
            'forced': 'false',
          });
          return http.Response('', 204);
        }),
      );
      await c.searchMissing(
        WantedSubtitle(
          title: 'Severance',
          subtitle: '',
          missing: const [],
          isMovie: false,
          seriesId: 5,
          episodeId: 77,
        ),
        SubLanguage(name: 'English', code: 'en', hi: true),
      );
    });
  });

  group('Notifications', () {
    test('topics are long, random and valid for ntfy', () {
      final t = randomTopic(Random(1));
      expect(t, matches(RegExp(r'^control_[a-z0-9]{20}$')));
      expect(randomTopic(Random(2)), isNot(t));
    });

    test('ntfy.sh target', () {
      final t = NtfyTarget.of(publicNtfy, 'control_abc');
      expect(t.publishUrl.toString(), 'https://ntfy.sh');
      expect(t.appriseUrl, 'ntfys://ntfy.sh/control_abc');
      expect(t.appUrl.toString(), 'ntfy://ntfy.sh/control_abc');
      expect(t.webUrl.toString(), 'https://ntfy.sh/control_abc');
    });

    test('self-hosted target: apps use home, phone uses away', () {
      final ntfy = ServerConfig(
        id: 'n',
        kind: ServiceKind.ntfy,
        name: 'ntfy',
        localUrl: '192.168.5.150:8080',
        remoteUrl: 'https://ntfy.example.com',
        apiKey: 'tk_secret',
      );
      final t = NtfyTarget.of(ntfy, 'control_abc');
      expect(t.publishUrl.toString(), 'http://192.168.5.150:8080');
      expect(t.appriseUrl, 'ntfy://tk_secret@192.168.5.150:8080/control_abc');
      expect(t.subscribeUrl.toString(), 'https://ntfy.example.com');
      final homeOnly = NtfyTarget.of(
        ntfy.copyWith(remoteUrl: ''),
        'control_abc',
      );
      expect(
        homeOnly.appUrl.toString(),
        'ntfy://192.168.5.150:8080/control_abc?secure=false',
      );
    });

    test('test message goes straight to the topic', () async {
      final c = NtfyClient(
        ServerConfig(
          id: 'n',
          kind: ServiceKind.ntfy,
          name: 'ntfy',
          localUrl: 'ntfy.local',
          apiKey: 'tk_1',
        ),
        httpClient: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '/control_abc');
          expect(req.headers['Title'], 'Hello');
          expect(req.headers['Authorization'], 'Bearer tk_1');
          expect(req.body, 'It works');
          return json({'id': 'x'});
        }),
      );
      await c.publish('control_abc', 'It works', title: 'Hello');
    });

    final schema = {
      'implementation': 'Ntfy',
      'configContract': 'NtfySettings',
      'name': '',
      'onGrab': false,
      'onDownload': false,
      'onUpgrade': false,
      'onHealthIssue': false,
      'onManualInteractionRequired': false,
      'includeHealthWarnings': true,
      'supportsOnGrab': true,
      'supportsOnDownload': true,
      'supportsOnUpgrade': true,
      'supportsOnHealthIssue': true,
      'supportsOnManualInteractionRequired': false,
      'presets': [],
      'tags': [],
      'fields': [
        {'name': 'serverUrl', 'value': null},
        {'name': 'accessToken', 'value': null},
        {'name': 'priority', 'value': 3},
        {'name': 'topics', 'value': []},
        {'name': 'tags', 'value': []},
      ],
    };

    test('*arr connection is filled from the schema', () {
      final body = ArrClient.ntfyBody(
        schema,
        NtfyTarget.of(publicNtfy, 'control_abc'),
        const NotifyEvents(grabs: true),
        existingId: 7,
      );
      expect(body['name'], 'Control');
      expect(body['id'], 7);
      expect(body.containsKey('presets'), isFalse);
      final fields = {
        for (final f in body['fields'] as List) f['name']: f['value'],
      };
      expect(fields['serverUrl'], 'https://ntfy.sh');
      expect(fields['topics'], ['control_abc']);
      expect(fields['accessToken'], '');
      expect(fields['tags'], []);
      expect(body['onGrab'], isTrue);
      expect(body['onDownload'], isTrue);
      expect(body['onUpgrade'], isTrue);
      expect(body['onHealthIssue'], isTrue);
      // Not supported by this app, so left off.
      expect(body['onManualInteractionRequired'], isFalse);
      expect(body['includeHealthWarnings'], isFalse);
      expect(body.containsKey('onReleaseImport'), isFalse);
    });

    test('setting up again updates Control\'s connection', () async {
      final calls = <String>[];
      final c = ArrClient(
        server(ServiceKind.radarr),
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('/schema')) return json([schema]);
          if (req.method == 'GET') {
            return json([
              {'id': 3, 'implementation': 'Ntfy', 'name': 'Other'},
              {'id': 9, 'implementation': 'Ntfy', 'name': 'Control'},
            ]);
          }
          expect(jsonDecode(req.body)['id'], 9);
          return json({'id': 9});
        }),
      );
      await c.connectNtfy(
        NtfyTarget.of(publicNtfy, 'control_abc'),
        const NotifyEvents(),
      );
      expect(calls, [
        'GET /api/v3/notification/schema',
        'GET /api/v3/notification',
        'PUT /api/v3/notification/9',
      ]);
    });

    test('SABnzbd keeps other Apprise URLs and replaces an old topic', () {
      final settings = SabnzbdClient.appriseSettings(
        'discord://a/b, ntfys://ntfy.sh/control_oldtopic123',
        NtfyTarget.of(publicNtfy, 'control_new'),
        const NotifyEvents(sabComplete: true),
      );
      expect(
        settings['apprise_urls'],
        'discord://a/b, ntfys://ntfy.sh/control_new',
      );
      expect(settings['apprise_enable'], '1');
      expect(settings['apprise_target_complete_enable'], '1');
      expect(settings['apprise_target_failed_enable'], '1');
    });

    test('SABnzbd setup writes through set_config', () async {
      final writes = <String, String>{};
      final c = SabnzbdClient(
        server(ServiceKind.sabnzbd),
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          if (q['mode'] == 'get_config') {
            expect(q['section'], 'apprise');
            return json({
              'config': {
                'apprise': {'apprise_urls': ''},
              },
            });
          }
          expect(q['mode'], 'set_config');
          writes[q['keyword']!] = q['value']!;
          return json({'status': true});
        }),
      );
      await c.connectNtfy(
        NtfyTarget.of(publicNtfy, 'control_abc'),
        const NotifyEvents(),
      );
      expect(writes['apprise_urls'], 'ntfys://ntfy.sh/control_abc');
      expect(writes['apprise_target_complete_enable'], '0');
    });

    test('settings round-trip', () {
      final s = NotifySettings(
        topic: 'control_abc',
        serverId: 'n',
        events: const NotifyEvents(grabs: true, problems: false),
      );
      final back = NotifySettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.topic, 'control_abc');
      expect(back.serverId, 'n');
      expect(back.events.grabs, isTrue);
      expect(back.events.problems, isFalse);
      expect(back.events.imports, isTrue);
      expect(s.copyWith(publicServer: true).serverId, isNull);
    });
  });

  group('Tracearr', () {
    test('streams, with relative posters made absolute', () {
      final a = TracearrClient.parseStreams({
        'data': [
          {
            'id': 'uuid-1',
            'serverName': 'Plex',
            'username': 'jeff',
            'mediaType': 'episode',
            'mediaTitle': 'Pilot',
            'showTitle': 'Severance',
            'seasonNumber': 1,
            'episodeNumber': 1,
            'durationMs': 4000,
            'progressMs': 1000,
            'state': 'paused',
            'isTranscode': true,
            'resolution': '1080p',
            'player': 'Infuse',
            'device': 'Apple TV',
            'posterUrl': '/api/v1/images/proxy?server=s&url=%2Fl%2F1&width=360',
          },
        ],
        'summary': {'total': 1, 'totalBitrate': '12.5 Mbps'},
      }, Uri.parse('http://192.168.5.150:3000'));
      final s = a.sessions.single;
      expect(s.title, 'Severance');
      expect(s.subtitle, 'S01E01 · Pilot');
      expect(s.player, 'Plex · Infuse · Apple TV');
      expect(s.progress, 0.25);
      expect(s.state, 'paused');
      expect(s.transcoding, isTrue);
      expect(s.quality, '1080p');
      expect(
        s.thumbUrl,
        'http://192.168.5.150:3000/api/v1/images/proxy?server=s&url=%2Fl%2F1&width=360',
      );
      expect(a.bandwidthKbps, 12500);
    });

    test('bitrate strings', () {
      expect(TracearrClient.parseBitrate('1.2 Gbps'), 1200000);
      expect(TracearrClient.parseBitrate('800 kbps'), 800);
      expect(TracearrClient.parseBitrate('—'), isNull);
    });

    test('history and alerts', () {
      final plays = TracearrClient.parseHistory({
        'data': [
          {
            'mediaType': 'movie',
            'mediaTitle': 'Dune',
            'year': 2021,
            'serverName': 'Emby',
            'durationMs': 3600000,
            'watched': true,
            'startedAt': '2026-10-05T20:00:00Z',
            'user': {'username': 'guest'},
            'posterUrl': 'https://plex.tv/p.jpg',
          },
        ],
        'meta': {'total': 1},
      }, null);
      expect(plays.single.title, 'Dune');
      expect(plays.single.subtitle, '2021');
      expect(plays.single.user, 'guest');
      expect(plays.single.watched, isTrue);
      expect(plays.single.posterUrl, 'https://plex.tv/p.jpg');
      final alerts = TracearrClient.parseAlerts({
        'data': [
          {
            'severity': 'high',
            'serverName': 'Plex',
            'createdAt': '2026-10-05T20:00:00Z',
            'rule': {'name': 'Concurrent streams'},
            'user': {'username': 'guest'},
          },
        ],
      });
      expect(alerts.single.rule, 'Concurrent streams');
      expect(alerts.single.severity, 'high');
    });

    test('Bearer key, health check and stopping a stream', () async {
      final calls = <String>[];
      final c = TracearrClient(
        server(ServiceKind.tracearr, apiKey: 'trr_pub_abc'),
        httpClient: MockClient((req) async {
          expect(req.headers['Authorization'], 'Bearer trr_pub_abc');
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('/health')) {
            return json({'status': 'ok', 'servers': []});
          }
          expect(jsonDecode(req.body), {'reason': 'Maintenance'});
          return json({'success': true});
        }),
      );
      await c.test();
      await c.terminate(
        PlaySession(id: 'uuid-1', title: 'x'),
        message: 'Maintenance',
      );
      expect(calls, [
        'GET /api/v1/public/health',
        'POST /api/v1/public/streams/uuid-1/terminate',
      ]);
    });
  });

  group('Comicarr', () {
    test('signs in, sends the session and CSRF header, retries on 401', () async {
      var logins = 0;
      var seriesCalls = 0;
      final c = ComicarrClient(
        server(ServiceKind.comicarr, user: 'jeff', pass: 'pw'),
        httpClient: MockClient((req) async {
          expect(req.headers['X-Requested-With'], 'ComicarrFrontend');
          if (req.url.path == '/api/auth/login') {
            logins++;
            expect(jsonDecode(req.body), {
              'username': 'jeff',
              'password': 'pw',
            });
            return json(
              {'success': true, 'username': 'jeff'},
              headers: {
                'set-cookie':
                    'comicarr_session=tok$logins; HttpOnly; Path=/; SameSite=strict',
              },
            );
          }
          seriesCalls++;
          if (req.headers['Cookie'] == 'comicarr_session=tok1') {
            return json({'detail': 'Session expired or invalid'}, status: 401);
          }
          expect(req.headers['Cookie'], 'comicarr_session=tok2');
          return json([
            {
              'ComicID': '4050',
              'ComicName': 'Saga',
              'ComicYear': '2012',
              'ComicImage': '/api/metadata/art/4050',
              'ComicImageURL': 'https://comicvine.gamespot.com/saga.jpg',
              'Status': 'Paused',
              'Total': 60,
              'Have': 45,
            },
          ]);
        }),
      );
      final series = await c.series();
      expect(logins, 2);
      expect(seriesCalls, 2);
      final s = series.single;
      expect(s.name, 'Saga');
      expect(s.paused, isTrue);
      expect(s.completion, 0.75);
      expect(s.coverUrl, 'https://comicvine.gamespot.com/saga.jpg');
    });

    test('wrong password shows Comicarr\'s message', () async {
      final c = ComicarrClient(
        server(ServiceKind.comicarr, user: 'jeff', pass: 'bad'),
        httpClient: MockClient(
          (_) async => json({
            'success': false,
            'error': 'Incorrect username or password.',
          }, status: 401),
        ),
      );
      await expectLater(
        c.series(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Comicarr: Incorrect username or password.',
          ),
        ),
      );
    });

    test('series without a provider cover uses Comicarr\'s own', () {
      final s = ComicarrClient.parseSeries({
        'comics': [
          {'ComicID': '1', 'ComicImage': '/api/metadata/art/1'},
        ],
      }, Uri.parse('http://192.168.5.150:8090'));
      expect(s.single.coverUrl, 'http://192.168.5.150:8090/api/metadata/art/1');
    });

    test('series detail, wanted and this week', () {
      final (series, issues) = ComicarrClient.parseDetail({
        'comic': [
          {'ComicID': '1', 'ComicName': 'Saga', 'Total': 2, 'Have': 1},
        ],
        'issues': [
          {
            'id': 'i2',
            'number': '2',
            'name': 'Two',
            'releaseDate': '2012-04-11',
            'displayState': 'Wanted',
          },
          {'id': 'i1', 'number': '1', 'displayState': 'Downloaded'},
        ],
      }, null);
      expect(series.name, 'Saga');
      expect(issues.map((i) => i.state), ['Wanted', 'Downloaded']);
      expect(issues.last.owned, isTrue);
      expect(issues.first.releaseDate, '2012-04-11');

      final wanted = ComicarrClient.parseWanted({
        'issues': [
          {
            'ComicName': 'Saga',
            'Issue_Number': '61',
            'IssueName': 'Return',
            'ReleaseDate': '2026-10-07',
            'ComicID': '1',
            'IssueID': 'i61',
            'Status': 'Wanted',
          },
        ],
      });
      expect(wanted.single.label, 'Saga #61');
      expect(wanted.single.issueId, 'i61');

      final week = ComicarrClient.parseUpcoming([
        {
          'ComicName': 'SAGA',
          'DisplayComicName': 'Saga',
          'IssueNumber': '61',
          'IssueDate': '2026-10-07',
          'Status': 'Downloaded',
          'ComicID': '1',
          'IssueID': 'i61',
        },
      ]);
      expect(week.single.label, 'Saga #61');
      expect(week.single.status, 'Downloaded');
    });

    test('search missing previews, then confirms with the token', () async {
      final calls = <String>[];
      final c = ComicarrClient(
        server(ServiceKind.comicarr, user: 'u', pass: 'p'),
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path == '/api/auth/login') {
            return json(
              {'success': true},
              headers: {'set-cookie': 'comicarr_session=t; Path=/'},
            );
          }
          if (req.method == 'GET') {
            return json({
              'eligibleCount': 3,
              'preview_token': 'pt',
              'fingerprint': 'fp',
            });
          }
          expect(jsonDecode(req.body), {
            'confirm': true,
            'preview_token': 'pt',
            'fingerprint': 'fp',
          });
          return json({'success': true, 'status': 'accepted'});
        }),
      );
      expect(await c.searchMissing('1'), 3);
      expect(calls, [
        'POST /api/auth/login',
        'GET /api/series/1/search-missing/preview',
        'POST /api/series/1/search-missing',
      ]);
    });
  });

  group('TMDB', () {
    test('trending today, in the same shape as Overseerr', () async {
      final c = TmdbClient(
        server(
          ServiceKind.tmdb,
          local: '',
          remote: TmdbClient.defaultUrl,
          apiKey: 'shortkey',
        ),
        httpClient: MockClient((req) async {
          expect(req.url.host, 'api.themoviedb.org');
          expect(req.url.path, '/3/trending/all/day');
          expect(req.url.queryParameters['api_key'], 'shortkey');
          expect(req.headers.containsKey('Authorization'), isFalse);
          return json({
            'results': [
              {
                'id': 1,
                'media_type': 'movie',
                'title': 'Film',
                'backdrop_path': '/b.jpg',
                'poster_path': '/p.jpg',
                'vote_average': 7.5,
                'release_date': '2026-09-30',
              },
              {'id': 2, 'media_type': 'person', 'name': 'Someone'},
              {
                'id': 3,
                'media_type': 'tv',
                'name': 'Show',
                'first_air_date': '2025-01-01',
              },
            ],
          });
        }),
      );
      final items = await c.discover(DiscoverFeed.trending);
      expect(items.map((i) => i.title), ['Film', 'Show']);
      expect(items.first.backdropUrl, 'https://image.tmdb.org/t/p/w1280/b.jpg');
      expect(items.first.rating, 7.5);
      expect(items.first.year, 2026);
      expect(items.first.canRequest, isTrue);
      expect(items.last.isTv, isTrue);
    });

    test('read access token goes in the Authorization header', () async {
      final token = 'eyJ${'a' * 60}';
      final c = TmdbClient(
        server(
          ServiceKind.tmdb,
          local: '',
          remote: TmdbClient.defaultUrl,
          apiKey: token,
        ),
        httpClient: MockClient((req) async {
          expect(req.headers['Authorization'], 'Bearer $token');
          expect(req.url.queryParameters.containsKey('api_key'), isFalse);
          expect(req.url.path, '/3/movie/popular');
          return json({
            'results': [
              {'id': 5, 'title': 'No type given'},
            ],
          });
        }),
      );
      final items = await c.discover(DiscoverFeed.popularMovies);
      expect(items.single.mediaType, 'movie');
    });

    test('feeds map to TMDB lists', () {
      expect(TmdbClient.pathFor(DiscoverFeed.upcomingTv), '/3/tv/on_the_air');
      expect(TmdbClient.pathFor(DiscoverFeed.popularTv), '/3/tv/popular');
    });

    test('Overseerr fills in availability for a TMDB title', () async {
      final c = OverseerrClient(
        server(ServiceKind.overseerr),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v1/tv/3');
          return json({
            'name': 'Show',
            'mediaInfo': {'status': 5},
          });
        }),
      );
      final r = await c.withStatus(
        TmdbClient.parse({
          'results': [
            {'id': 3, 'media_type': 'tv', 'name': 'Show'},
          ],
        }).single,
      );
      expect(r.availabilityLabel, 'Available');
      expect(r.canRequest, isFalse);
    });
  });

  group('Editing and choosing releases', () {
    MediaItem series(Map<String, dynamic> raw) =>
        ArrClient(server(ServiceKind.sonarr)).toMedia(raw);

    test('edit starts from what the *arr has', () {
      final e = MediaEdit.of(
        series({
          'id': 1,
          'title': 'Severance',
          'monitored': true,
          'qualityProfileId': 4,
          'languageProfileId': 1,
          'seriesType': 'standard',
          'seasonFolder': true,
          'path': '/tv/Severance',
        }),
      );
      expect(e.rootFolderPath, '/tv');
      expect(e.qualityProfileId, 4);
      expect(e.languageProfileId, 1);
      expect(e.seriesType, 'standard');
      expect(e.minimumAvailability, isNull);
    });

    test('changing the folder moves the item into it', () {
      final item = series({
        'id': 1,
        'title': 'Severance',
        'qualityProfileId': 4,
        'path': '/tv/Severance',
        'rootFolderPath': '/tv/',
      });
      final e = MediaEdit.of(item)
        ..rootFolderPath = '/tv4k'
        ..qualityProfileId = 7
        ..monitored = false;
      final body = ArrClient.editBody(item, e);
      expect(body['path'], '/tv4k/Severance');
      expect(body['rootFolderPath'], '/tv4k');
      expect(body['qualityProfileId'], 7);
      expect(body['monitored'], isFalse);
      expect(body['title'], 'Severance');

      final same = ArrClient.editBody(item, MediaEdit.of(item));
      expect(same['path'], '/tv/Severance');
    });

    test('Windows paths', () {
      expect(MediaEdit.parentOf(r'D:\Movies\Dune (2021)'), r'D:\Movies');
      expect(MediaEdit.folderOf(r'D:\Movies\Dune (2021)\'), 'Dune (2021)');
    });

    test('saving sends moveFiles only when the folder changed', () async {
      final item = ArrClient(server(ServiceKind.radarr)).toMedia({
        'id': 9,
        'title': 'Dune',
        'qualityProfileId': 1,
        'minimumAvailability': 'released',
        'path': '/movies/Dune',
      });
      final c = ArrClient(
        server(ServiceKind.radarr),
        httpClient: MockClient((req) async {
          expect(req.method, 'PUT');
          expect(req.url.path, '/api/v3/movie/9');
          expect(req.url.queryParameters['moveFiles'], 'true');
          final body = jsonDecode(req.body) as Map;
          expect(body['minimumAvailability'], 'inCinemas');
          return json(body);
        }),
      );
      final e = MediaEdit.of(item)
        ..rootFolderPath = '/movies-4k'
        ..minimumAvailability = 'inCinemas';
      final updated = await c.update(item, e);
      expect(updated.raw['path'], '/movies-4k/Dune');
    });

    test('releases: approved first, then score, then size', () {
      final sorted = ArrClient.sortReleases([
        ArrRelease({
          'title': 'rejected',
          'rejected': true,
          'customFormatScore': 900,
        }),
        ArrRelease({'title': 'small', 'customFormatScore': 100, 'size': 1}),
        ArrRelease({'title': 'big', 'customFormatScore': 100, 'size': 9}),
        ArrRelease({'title': 'best', 'customFormatScore': 500}),
      ]);
      expect(sorted.map((r) => r.title), ['best', 'big', 'small', 'rejected']);
    });

    test('grab sends the guid and indexer', () async {
      final c = ArrClient(
        server(ServiceKind.sonarr),
        httpClient: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '/api/v3/release');
          expect(jsonDecode(req.body), {'guid': 'g1', 'indexerId': 3});
          return json({});
        }),
      );
      await c.grab(ArrRelease({'guid': 'g1', 'indexerId': 3}));
    });

    test('calendar entries know which series to open', () async {
      final c = ArrClient(
        server(ServiceKind.sonarr),
        httpClient: MockClient(
          (_) async => json([
            {
              'seriesId': 42,
              'seasonNumber': 1,
              'episodeNumber': 2,
              'title': 'Half Loop',
              'airDateUtc': '2026-10-06T01:00:00Z',
              'series': {'title': 'Severance'},
            },
          ]),
        ),
      );
      final entries = await c.calendar(
        DateTime.utc(2026, 10, 5),
        DateTime.utc(2026, 10, 12),
      );
      expect(entries.single.mediaId, 42);
    });
  });
}

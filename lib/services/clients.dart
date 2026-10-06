import 'package:http/http.dart' as http;

import '../models/server.dart';
import 'arr.dart';
import 'bazarr.dart';
import 'media_server.dart';
import 'nzbget.dart';
import 'overseerr.dart';
import 'prowlarr.dart';
import 'qbittorrent.dart';
import 'sabnzbd.dart';
import 'service_client.dart';
import 'tautulli.dart';
import 'transmission.dart';

export 'service_client.dart';

ServiceClient createClient(ServerConfig server, {http.Client? httpClient}) =>
    switch (server.kind) {
      ServiceKind.sabnzbd => SabnzbdClient(server, httpClient: httpClient),
      ServiceKind.nzbget => NzbgetClient(server, httpClient: httpClient),
      ServiceKind.qbittorrent => QbittorrentClient(
        server,
        httpClient: httpClient,
      ),
      ServiceKind.transmission => TransmissionClient(
        server,
        httpClient: httpClient,
      ),
      ServiceKind.sonarr ||
      ServiceKind.radarr ||
      ServiceKind.lidarr => ArrClient(server, httpClient: httpClient),
      ServiceKind.prowlarr => ProwlarrClient(server, httpClient: httpClient),
      ServiceKind.overseerr => OverseerrClient(server, httpClient: httpClient),
      ServiceKind.tautulli => TautulliClient(server, httpClient: httpClient),
      ServiceKind.emby ||
      ServiceKind.jellyfin => MediaServerClient(server, httpClient: httpClient),
      ServiceKind.bazarr => BazarrClient(server, httpClient: httpClient),
    };

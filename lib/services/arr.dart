import '../models/server.dart';
import '../util/format.dart';
import 'ntfy.dart';
import 'service_client.dart';

/// A series (Sonarr), movie (Radarr) or artist (Lidarr), as shown in lists.
class MediaItem {
  MediaItem({
    required this.id,
    required this.title,
    required this.raw,
    this.year,
    this.overview = '',
    this.posterUrl,
    this.fanartUrl,
    this.monitored = false,
    this.status = '',
    this.sizeOnDisk = 0,
    this.haveCount = 0,
    this.totalCount = 0,
    this.hasFile = false,
    this.network,
  });

  /// 0 for lookup results that aren't in the library yet.
  final int id;
  final String title;
  final int? year;
  final String overview;
  final String? posterUrl;
  final String? fanartUrl;
  final bool monitored;
  final String status;
  final int sizeOnDisk;

  /// Episodes/tracks on disk vs. expected (Sonarr, Lidarr).
  final int haveCount;
  final int totalCount;

  /// Radarr: the movie file is on disk.
  final bool hasFile;
  final String? network;
  final Map<String, dynamic> raw;

  bool get inLibrary => id > 0;
}

/// A Sonarr episode.
class Episode {
  Episode(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  int get season => asInt(raw['seasonNumber']);
  int get number => asInt(raw['episodeNumber']);
  String get title => (raw['title'] ?? 'TBA').toString();
  bool get hasFile => raw['hasFile'] == true;
  bool get monitored => raw['monitored'] == true;
  DateTime? get airDate => parseDate(raw['airDateUtc']);
  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
}

/// Something coming up, from any *arr calendar.
class CalendarEntry {
  CalendarEntry({
    required this.when,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.serverId,
    this.posterUrl,
    this.hasFile = false,
  });

  final DateTime when;
  final String title;
  final String subtitle;
  final ServiceKind kind;
  final String serverId;
  final String? posterUrl;
  final bool hasFile;
}

/// An item in an *arr download queue.
class ArrQueueItem {
  ArrQueueItem(this.raw);
  final Map<String, dynamic> raw;

  int get id => asInt(raw['id']);
  String get title => (raw['title'] ?? '').toString();
  String get status => (raw['status'] ?? '').toString();
  String get trackedState => (raw['trackedDownloadState'] ?? '').toString();
  bool get hasWarning =>
      raw['trackedDownloadStatus'] == 'warning' ||
      raw['trackedDownloadStatus'] == 'error';
  List<String> get messages => [
    for (final m in (raw['statusMessages'] as List? ?? const []))
      for (final s in ((m as Map)['messages'] as List? ?? const []))
        s.toString(),
  ];
  double get progress {
    final size = asDouble(raw['size']);
    return size > 0
        ? ((size - asDouble(raw['sizeleft'])) / size).clamp(0, 1).toDouble()
        : 0;
  }

  int get sizeBytes => asInt(raw['size']);
  String get downloadClient => (raw['downloadClient'] ?? '').toString();
  String get protocol => (raw['protocol'] ?? '').toString();
}

/// Something an *arr is downloading, with artwork, for the Home banner.
/// Episodes from one season pack are folded into a single entry.
class ActiveDownload {
  ActiveDownload({
    required this.kind,
    required this.serverId,
    required this.title,
    this.subtitle = '',
    this.posterUrl,
    this.fanartUrl,
    this.progress = 0,
    this.status = '',
    this.timeLeft,
    this.hasWarning = false,
  });

  final ServiceKind kind;
  final String serverId;
  final String title;
  final String subtitle;
  final String? posterUrl;
  final String? fanartUrl;
  final double progress;

  /// The *arr's queue status: downloading, paused, queued, delay, completed…
  final String status;
  final Duration? timeLeft;
  final bool hasWarning;

  bool get isDownloading => status == 'downloading';
}

/// *arr time left, a .NET TimeSpan: "00:12:05" or "1.02:03:04".
Duration? parseTimeSpan(Object? v) {
  final s = v?.toString() ?? '';
  final m = RegExp(r'^(?:(\d+)\.)?(\d+):(\d+):(\d+)').firstMatch(s);
  if (m == null) return null;
  return Duration(
    days: int.parse(m[1] ?? '0'),
    hours: int.parse(m[2]!),
    minutes: int.parse(m[3]!),
    seconds: int.parse(m[4]!),
  );
}

class Profile {
  Profile(this.id, this.name);
  final int id;
  final String name;
}

class RootFolder {
  RootFolder(this.path, this.freeSpace);
  final String path;
  final int freeSpace;
}

/// Sonarr, Radarr and Lidarr share an API shape; this covers all three.
class ArrClient extends ServiceClient {
  ArrClient(super.server, {super.httpClient});

  ServiceKind get kind => server.kind;
  String get _v => kind == ServiceKind.lidarr ? '/api/v1' : '/api/v3';

  /// "series", "movie" or "artist".
  String get resource => switch (kind) {
    ServiceKind.sonarr => 'series',
    ServiceKind.radarr => 'movie',
    _ => 'artist',
  };

  String get itemNoun => switch (kind) {
    ServiceKind.sonarr => 'series',
    ServiceKind.radarr => 'movie',
    _ => 'artist',
  };

  @override
  Map<String, String> authHeaders() => {'X-Api-Key': server.apiKey};

  @override
  Future<void> test() async {
    final status = await getJson('$_v/system/status');
    if (status is! Map || status['version'] == null) {
      throw ApiException('That address answered, but it isn\'t ${kind.label}.');
    }
  }

  Future<List<MediaItem>> library() async {
    final list = await getJson('$_v/$resource') as List;
    final items = [for (final m in list) toMedia((m as Map).cast())];
    items.sort((a, b) => _sortKey(a.title).compareTo(_sortKey(b.title)));
    return items;
  }

  static String _sortKey(String t) =>
      t.toLowerCase().replaceFirst(RegExp(r'^(the|a|an) '), '');

  Future<MediaItem> item(int id) async =>
      toMedia((await getJson('$_v/$resource/$id') as Map).cast());

  Future<List<MediaItem>> lookup(String term) async {
    final list =
        await getJson('$_v/$resource/lookup', query: {'term': term}) as List;
    return [for (final m in list) toMedia((m as Map).cast())];
  }

  MediaItem toMedia(Map<String, dynamic> m) {
    final stats =
        (m['statistics'] as Map?)?.cast<String, dynamic>() ?? const {};
    final title = (m['title'] ?? m['artistName'] ?? '').toString();
    final year = asInt(m['year']);
    return MediaItem(
      id: asInt(m['id']),
      title: title,
      year: year > 0 ? year : null,
      overview: (m['overview'] ?? '').toString(),
      posterUrl:
          imageUrl(m, kind == ServiceKind.lidarr ? 'poster' : 'poster') ??
          imageUrl(m, 'cover'),
      fanartUrl: imageUrl(m, 'fanart'),
      monitored: m['monitored'] == true,
      status: (m['status'] ?? '').toString(),
      sizeOnDisk: asInt(stats['sizeOnDisk'] ?? m['sizeOnDisk']),
      haveCount: asInt(stats['episodeFileCount'] ?? stats['trackFileCount']),
      totalCount: asInt(
        stats['episodeCount'] ??
            stats['totalTrackCount'] ??
            stats['trackCount'],
      ),
      hasFile: m['hasFile'] == true,
      network: m['network'] as String?,
      raw: m,
    );
  }

  /// The public poster URL when the *arr gives one; otherwise the server's
  /// own copy, fetched with the API key.
  String? imageUrl(Map<String, dynamic> m, String type) {
    final images = (m['images'] as List?)?.cast<Map>() ?? const [];
    final img = images.where((i) => i['coverType'] == type).firstOrNull;
    if (img == null) return null;
    final remote = img['remoteUrl'] as String?;
    if (remote != null && remote.startsWith('http')) return remote;
    final local = img['url'] as String?;
    if (local == null || local.isEmpty) return null;
    if (local.startsWith('http')) return local;
    final base = activeBase ?? server.baseUris.firstOrNull;
    if (base == null) return null;
    final u = Uri.parse(local);
    return joinUri(base, u.path, {
      ...u.queryParameters,
      'apikey': server.apiKey,
    }).toString();
  }

  // ---- Episodes (Sonarr) ----

  Future<List<Episode>> episodes(int seriesId) async {
    final list =
        await getJson('$_v/episode', query: {'seriesId': '$seriesId'}) as List;
    return [for (final e in list) Episode((e as Map).cast())];
  }

  Future<void> setEpisodesMonitored(List<int> ids, bool monitored) => sendJson(
    'PUT',
    '$_v/episode/monitor',
    json: {'episodeIds': ids, 'monitored': monitored},
  );

  // ---- Changes ----

  Future<MediaItem> setMonitored(MediaItem item, bool monitored) async {
    final body = {...item.raw, 'monitored': monitored};
    final res = await sendJson('PUT', '$_v/$resource/${item.id}', json: body);
    return toMedia((res as Map).cast());
  }

  /// Sets monitoring on one Sonarr season.
  Future<MediaItem> setSeasonMonitored(
    MediaItem series,
    int season,
    bool monitored,
  ) async {
    final seasons = [
      for (final s in (series.raw['seasons'] as List? ?? const []))
        {
          ...(s as Map).cast<String, dynamic>(),
          if (asInt(s['seasonNumber']) == season) 'monitored': monitored,
        },
    ];
    final res = await sendJson(
      'PUT',
      '$_v/series/${series.id}',
      json: {...series.raw, 'seasons': seasons},
    );
    return toMedia((res as Map).cast());
  }

  Future<void> delete(MediaItem item, {bool deleteFiles = false}) => request(
    'DELETE',
    '$_v/$resource/${item.id}',
    query: {'deleteFiles': '$deleteFiles', 'addImportExclusion': 'false'},
  );

  /// Searches indexers for everything missing on [item].
  Future<void> searchItem(MediaItem item) => command(switch (kind) {
    ServiceKind.sonarr => {'name': 'SeriesSearch', 'seriesId': item.id},
    ServiceKind.radarr => {
      'name': 'MoviesSearch',
      'movieIds': [item.id],
    },
    _ => {'name': 'ArtistSearch', 'artistId': item.id},
  });

  Future<void> searchSeason(int seriesId, int season) => command({
    'name': 'SeasonSearch',
    'seriesId': seriesId,
    'seasonNumber': season,
  });

  Future<void> searchEpisodes(List<int> ids) =>
      command({'name': 'EpisodeSearch', 'episodeIds': ids});

  Future<void> refresh(MediaItem item) => command(switch (kind) {
    ServiceKind.sonarr => {'name': 'RefreshSeries', 'seriesId': item.id},
    ServiceKind.radarr => {
      'name': 'RefreshMovie',
      'movieIds': [item.id],
    },
    _ => {'name': 'RefreshArtist', 'artistId': item.id},
  });

  Future<void> command(Map<String, Object?> body) =>
      sendJson('POST', '$_v/command', json: body);

  // ---- Adding ----

  Future<List<Profile>> qualityProfiles() => _profiles('qualityprofile');
  Future<List<Profile>> metadataProfiles() => _profiles('metadataprofile');

  /// Sonarr v3 needs a language profile; v4 dropped them (404 → empty).
  Future<List<Profile>> languageProfiles() async {
    try {
      return await _profiles('languageprofile');
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) return const [];
      rethrow;
    }
  }

  Future<List<Profile>> _profiles(String path) async {
    final list = await getJson('$_v/$path') as List;
    return [
      for (final p in list)
        Profile(asInt((p as Map)['id']), (p['name'] ?? '').toString()),
    ];
  }

  Future<List<RootFolder>> rootFolders() async {
    final list = await getJson('$_v/rootfolder') as List;
    return [
      for (final r in list)
        RootFolder((r as Map)['path'].toString(), asInt(r['freeSpace'])),
    ];
  }

  /// Builds the body to add [result] (a lookup result) to the library.
  Map<String, dynamic> addBody(
    MediaItem result, {
    required int qualityProfileId,
    required String rootFolderPath,
    int? languageProfileId,
    int? metadataProfileId,
    bool search = true,
    String monitor = 'all',
    String minimumAvailability = 'released',
  }) {
    final body = <String, dynamic>{
      ...result.raw,
      'qualityProfileId': qualityProfileId,
      'rootFolderPath': rootFolderPath,
      'monitored': monitor != 'none',
    };
    switch (kind) {
      case ServiceKind.sonarr:
        body['seasonFolder'] = true;
        if (languageProfileId != null) {
          body['languageProfileId'] = languageProfileId;
        }
        body['addOptions'] = {
          'monitor': monitor,
          'searchForMissingEpisodes': search,
          'searchForCutoffUnmetEpisodes': false,
        };
      case ServiceKind.radarr:
        body['minimumAvailability'] = minimumAvailability;
        body['addOptions'] = {
          'monitor': monitor == 'none' ? 'none' : 'movieOnly',
          'searchForMovie': search,
        };
      default:
        if (metadataProfileId != null) {
          body['metadataProfileId'] = metadataProfileId;
        }
        body['addOptions'] = {
          'monitor': monitor,
          'searchForMissingAlbums': search,
        };
    }
    return body;
  }

  Future<MediaItem> add(Map<String, dynamic> body) async => toMedia(
    (await sendJson('POST', '$_v/$resource', json: body) as Map).cast(),
  );

  // ---- Queue ----

  Future<List<ArrQueueItem>> queue() async {
    final json = await getJson(
      '$_v/queue',
      query: {
        'page': '1',
        'pageSize': '100',
        if (kind == ServiceKind.sonarr) ...{
          'includeSeries': 'true',
          'includeEpisode': 'true',
        },
        if (kind == ServiceKind.radarr) 'includeMovie': 'true',
        if (kind == ServiceKind.lidarr) ...{
          'includeArtist': 'true',
          'includeAlbum': 'true',
        },
      },
    );
    final records = json is Map ? json['records'] as List : json as List;
    return [for (final r in records) ArrQueueItem((r as Map).cast())];
  }

  /// The queue with artwork, active downloads first.
  Future<List<ActiveDownload>> activeDownloads() async =>
      toActive(await queue());

  /// Folds queue records into [ActiveDownload]s: records sharing a download
  /// (a season pack) become one entry.
  List<ActiveDownload> toActive(List<ArrQueueItem> items) {
    final groups = <String, List<ArrQueueItem>>{};
    for (final q in items) {
      final key = (q.raw['downloadId'] ?? 'id${q.id}').toString();
      groups.putIfAbsent(key, () => []).add(q);
    }
    final out = <ActiveDownload>[];
    for (final group in groups.values) {
      final q = group.first;
      final media =
          ((q.raw['series'] ?? q.raw['movie'] ?? q.raw['artist']) as Map?)
              ?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final title = (media['title'] ?? media['artistName'] ?? '').toString();
      out.add(
        ActiveDownload(
          kind: kind,
          serverId: server.id,
          title: title.isEmpty ? q.title : title,
          subtitle: _queueSubtitle(group, media),
          posterUrl: imageUrl(media, 'poster') ?? imageUrl(media, 'cover'),
          fanartUrl: imageUrl(media, 'fanart'),
          progress: q.progress,
          status: q.status.toLowerCase(),
          timeLeft: parseTimeSpan(q.raw['timeleft']),
          hasWarning: q.hasWarning,
        ),
      );
    }
    out.sort((a, b) {
      if (a.isDownloading != b.isDownloading) return a.isDownloading ? -1 : 1;
      return b.progress.compareTo(a.progress);
    });
    return out;
  }

  String _queueSubtitle(List<ArrQueueItem> group, Map<String, dynamic> media) {
    final q = group.first;
    switch (kind) {
      case ServiceKind.sonarr:
        final ep = (q.raw['episode'] as Map?)?.cast<String, dynamic>();
        if (ep == null) return '';
        final e = Episode(ep);
        if (group.length > 1) {
          return 'Season ${e.season} · ${group.length} episodes';
        }
        return '${e.code} · ${e.title}';
      case ServiceKind.radarr:
        final year = asInt(media['year']);
        return year > 0 ? '$year' : '';
      default:
        return ((q.raw['album'] as Map?)?['title'] ?? '').toString();
    }
  }

  Future<void> removeFromQueue(
    ArrQueueItem item, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) => request(
    'DELETE',
    '$_v/queue/${item.id}',
    query: {'removeFromClient': '$removeFromClient', 'blocklist': '$blocklist'},
  );

  // ---- Notifications ----

  /// Name of the connection Control creates, so setting up again updates it.
  static const notificationName = 'Control';

  /// Adds (or updates) an ntfy connection under Settings → Connect.
  Future<void> connectNtfy(NtfyTarget target, NotifyEvents events) async {
    final schema = await getJson('$_v/notification/schema') as List;
    final ntfy = schema
        .cast<Map>()
        .where((m) => m['implementation'] == 'Ntfy')
        .firstOrNull;
    if (ntfy == null) {
      throw ApiException(
        '${kind.label} on ${server.name} is too old to send ntfy notifications.',
      );
    }
    final existing = (await getJson('$_v/notification') as List)
        .cast<Map>()
        .where(
          (m) => m['implementation'] == 'Ntfy' && m['name'] == notificationName,
        )
        .firstOrNull;
    final body = ntfyBody(
      ntfy.cast(),
      target,
      events,
      existingId: existing == null ? null : asInt(existing['id']),
    );
    if (existing == null) {
      await sendJson('POST', '$_v/notification', json: body);
    } else {
      await sendJson('PUT', '$_v/notification/${body['id']}', json: body);
    }
  }

  /// Fills in the ntfy template from `/notification/schema`. Only switches the
  /// app reports as supported are turned on, so it works across Sonarr,
  /// Radarr and Lidarr versions.
  static Map<String, dynamic> ntfyBody(
    Map<String, dynamic> schema,
    NtfyTarget target,
    NotifyEvents events, {
    int? existingId,
  }) {
    final body = Map<String, dynamic>.of(schema)
      ..['name'] = notificationName
      ..remove('presets');
    if (existingId != null) body['id'] = existingId;
    body['fields'] = [
      for (final f in (schema['fields'] as List? ?? const []))
        if (f is Map)
          {
            ...f.cast<String, dynamic>(),
            'value': switch (f['name']) {
              'serverUrl' => target.publishUrl.toString(),
              'accessToken' => target.token,
              'topics' => [target.topic],
              'priority' => 3,
              _ => f['value'],
            },
          },
    ];
    const groups = {
      'grabs': ['onGrab'],
      'imports': [
        'onDownload',
        'onUpgrade',
        'onImportComplete',
        'onReleaseImport',
        'onAlbumDownload',
      ],
      'problems': [
        'onHealthIssue',
        'onManualInteractionRequired',
        'onDownloadFailure',
        'onImportFailure',
      ],
    };
    final wanted = {
      'grabs': events.grabs,
      'imports': events.imports,
      'problems': events.problems,
    };
    for (final MapEntry(key: group, value: flags) in groups.entries) {
      for (final flag in flags) {
        if (!body.containsKey(flag)) continue;
        final supports = 'supports${flag[0].toUpperCase()}${flag.substring(1)}';
        body[flag] = wanted[group]! && body[supports] != false;
      }
    }
    if (body.containsKey('includeHealthWarnings')) {
      body['includeHealthWarnings'] = false;
    }
    return body;
  }

  // ---- Calendar ----

  Future<List<CalendarEntry>> calendar(DateTime start, DateTime end) async {
    final list = await getJson(
      '$_v/calendar',
      query: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'unmonitored': 'false',
        if (kind == ServiceKind.sonarr) 'includeSeries': 'true',
        if (kind == ServiceKind.lidarr) 'includeArtist': 'true',
      },
    ) as List;
    final entries = <CalendarEntry>[];
    for (final e in list) {
      final m = (e as Map).cast<String, dynamic>();
      switch (kind) {
        case ServiceKind.sonarr:
          final ep = Episode(m);
          final series =
              (m['series'] as Map?)?.cast<String, dynamic>() ?? const {};
          final when = ep.airDate;
          if (when == null) continue;
          entries.add(
            CalendarEntry(
              when: when,
              title: (series['title'] ?? '').toString(),
              subtitle: '${ep.code} · ${ep.title}',
              kind: kind,
              serverId: server.id,
              posterUrl: imageUrl(series, 'poster'),
              hasFile: ep.hasFile,
            ),
          );
        case ServiceKind.radarr:
          // Show the next release that falls in the window.
          for (final (key, label) in const [
            ('inCinemas', 'In cinemas'),
            ('digitalRelease', 'Digital release'),
            ('physicalRelease', 'Physical release'),
          ]) {
            final d = parseDate(m[key]);
            if (d != null && !d.isBefore(start) && d.isBefore(end)) {
              entries.add(
                CalendarEntry(
                  when: d,
                  title: (m['title'] ?? '').toString(),
                  subtitle: label,
                  kind: kind,
                  serverId: server.id,
                  posterUrl: imageUrl(m, 'poster'),
                  hasFile: m['hasFile'] == true,
                ),
              );
            }
          }
        default:
          final d = parseDate(m['releaseDate']);
          if (d == null) continue;
          final artist =
              (m['artist'] as Map?)?.cast<String, dynamic>() ?? const {};
          entries.add(
            CalendarEntry(
              when: d,
              title: (artist['artistName'] ?? '').toString(),
              subtitle: (m['title'] ?? '').toString(),
              kind: kind,
              serverId: server.id,
              posterUrl: imageUrl(m, 'cover') ?? imageUrl(artist, 'poster'),
              hasFile:
                  asInt((m['statistics'] as Map?)?['percentOfTracks']) >= 100,
            ),
          );
      }
    }
    return entries;
  }
}

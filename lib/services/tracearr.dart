import '../util/format.dart';
import 'service_client.dart';
import 'streaming.dart';

export 'streaming.dart';

/// Today's numbers from Tracearr's dashboard.
class TracearrToday {
  TracearrToday(this.raw);
  final Map<String, dynamic> raw;

  int get activeStreams => asInt(raw['activeStreams']);
  int get plays => asInt(raw['todayPlays']);
  double get watchHours => asDouble(raw['watchTimeHours']);
  int get activeUsers => asInt(raw['activeUsersToday']);
  int get alerts => asInt(raw['alertsLast24h']);
}

/// One play in Tracearr's history.
class TracearrPlay {
  TracearrPlay({
    required this.title,
    required this.subtitle,
    required this.user,
    required this.server,
    this.posterUrl,
    this.startedAt,
    this.watchedMs = 0,
    this.watched = false,
    this.transcode = false,
    this.player = '',
  });

  final String title;
  final String subtitle;
  final String user;
  final String server;
  final String? posterUrl;
  final DateTime? startedAt;
  final int watchedMs;
  final bool watched;
  final bool transcode;
  final String player;
}

/// A rule Tracearr flagged (account sharing, too many streams…).
class TracearrAlert {
  TracearrAlert({
    required this.rule,
    required this.user,
    required this.severity,
    required this.server,
    this.createdAt,
  });
  final String rule;
  final String user;

  /// low, warning or high.
  final String severity;
  final String server;
  final DateTime? createdAt;
}

/// Tracearr, through its public API (`/api/v1/public`, Bearer `trr_pub_…`
/// key). It watches Plex, Jellyfin and Emby together, so it is also a
/// [StreamingClient] for Now playing.
class TracearrClient extends ServiceClient implements StreamingClient {
  TracearrClient(super.server, {super.httpClient});

  static const _p = '/api/v1/public';

  @override
  Map<String, String> authHeaders() => {
    'Authorization': 'Bearer ${server.apiKey.trim()}',
  };

  Uri? get _base => activeBase ?? server.baseUris.firstOrNull;

  @override
  Future<void> test() async {
    final json = await getJson('$_p/health');
    if (json is! Map || json['status'] != 'ok') {
      throw ApiException('That address answered, but it isn\'t Tracearr.');
    }
  }

  @override
  Future<Activity> activity() async =>
      parseStreams(await getJson('$_p/streams'), _base);

  @override
  Future<void> terminate(PlaySession s, {String message = ''}) => sendJson(
    'POST',
    '$_p/streams/${s.id}/terminate',
    json: {if (message.isNotEmpty) 'reason': message},
  );

  /// Today's plays, watch time and alerts. Tracearr counts "today" in UTC
  /// unless told an IANA zone, which the phone doesn't expose without a
  /// plugin, so the day can roll over a few hours early or late.
  Future<TracearrToday> today() async =>
      TracearrToday((await getJson('$_p/stats/today') as Map).cast());

  Future<List<TracearrPlay>> history({int pageSize = 40}) async =>
      parseHistory(
        await getJson('$_p/history', query: {'pageSize': '$pageSize'}),
        _base,
      );

  Future<List<TracearrAlert>> alerts() async => parseAlerts(
    await getJson('$_p/violations', query: {'pageSize': '30'}),
  );

  /// Poster URLs come back relative to the Tracearr address and need no key.
  static String? absolute(Uri? base, Object? url) {
    final u = url?.toString() ?? '';
    if (u.isEmpty) return null;
    if (u.startsWith('http')) return u;
    if (base == null) return null;
    final rel = Uri.parse(u);
    return joinUri(base, rel.path, rel.queryParameters).toString();
  }

  static String _subtitle(Map m) {
    if (m['mediaType'] == 'episode') {
      final s = asInt(m['seasonNumber']).toString().padLeft(2, '0');
      final e = asInt(m['episodeNumber']).toString().padLeft(2, '0');
      return 'S${s}E$e · ${m['mediaTitle'] ?? ''}';
    }
    if (m['mediaType'] == 'track') {
      return [
        m['mediaTitle'],
        m['albumName'],
      ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    }
    final year = asInt(m['year']);
    return year > 0 ? '$year' : '';
  }

  static String _title(Map m) => switch (m['mediaType']) {
    'episode' => (m['showTitle'] ?? m['mediaTitle'] ?? '').toString(),
    'track' => (m['artistName'] ?? m['mediaTitle'] ?? '').toString(),
    _ => (m['mediaTitle'] ?? '').toString(),
  };

  static Activity parseStreams(Object? json, Uri? base) {
    final data = json is Map ? json['data'] : null;
    final sessions = <PlaySession>[];
    for (final m in data is List ? data : const []) {
      if (m is! Map) continue;
      final duration = asDouble(m['durationMs']);
      final progress = asDouble(m['progressMs']);
      sessions.add(
        PlaySession(
          id: (m['id'] ?? '').toString(),
          title: _title(m),
          subtitle: _subtitle(m),
          user: (m['username'] ?? '').toString(),
          player: [
            m['serverName'],
            m['player'] ?? m['product'],
            m['device'],
          ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
          progress: duration > 0
              ? (progress / duration).clamp(0, 1).toDouble()
              : 0,
          state: (m['state'] ?? 'playing').toString(),
          transcoding: m['isTranscode'] == true,
          quality: (m['resolution'] ?? '').toString(),
          thumbUrl: absolute(base, m['posterUrl']),
        ),
      );
    }
    final summary = json is Map ? json['summary'] : null;
    return Activity(
      sessions,
      bandwidthKbps: summary is Map
          ? parseBitrate(summary['totalBitrate'])
          : null,
    );
  }

  /// "45.2 Mbps" → 45200 (kbps). Tracearr shows "—" when idle.
  static int? parseBitrate(Object? v) {
    final m = RegExp(
      r'([\d.]+)\s*([kMG])bps',
    ).firstMatch(v?.toString() ?? '');
    if (m == null) return null;
    final n = double.parse(m[1]!);
    return (n * switch (m[2]) {
              'G' => 1000000,
              'M' => 1000,
              _ => 1,
            })
        .round();
  }

  static List<TracearrPlay> parseHistory(Object? json, Uri? base) {
    final data = json is Map ? json['data'] : null;
    return [
      for (final m in data is List ? data : const [])
        if (m is Map)
          TracearrPlay(
            title: _title(m),
            subtitle: _subtitle(m),
            user: ((m['user'] as Map?)?['username'] ?? '').toString(),
            server: (m['serverName'] ?? '').toString(),
            posterUrl: absolute(base, m['posterUrl']),
            startedAt: parseDate(m['startedAt']),
            watchedMs: asInt(m['durationMs']),
            watched: m['watched'] == true,
            transcode: m['isTranscode'] == true,
            player: (m['player'] ?? m['product'] ?? '').toString(),
          ),
    ];
  }

  static List<TracearrAlert> parseAlerts(Object? json) {
    final data = json is Map ? json['data'] : null;
    return [
      for (final m in data is List ? data : const [])
        if (m is Map)
          TracearrAlert(
            rule: ((m['rule'] as Map?)?['name'] ?? 'Rule').toString(),
            user: ((m['user'] as Map?)?['username'] ?? '').toString(),
            severity: (m['severity'] ?? '').toString(),
            server: (m['serverName'] ?? '').toString(),
            createdAt: parseDate(m['createdAt']),
          ),
    ];
  }
}

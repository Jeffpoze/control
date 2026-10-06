import '../util/format.dart';
import 'service_client.dart';

const tmdbImageBase = 'https://image.tmdb.org/t/p/w342';
const tmdbBackdropBase = 'https://image.tmdb.org/t/p/w1280';

/// The lists Overseerr offers on its Discover page.
enum DiscoverFeed {
  trending('Trending now', '/api/v1/discover/trending'),
  popularMovies('Popular movies', '/api/v1/discover/movies', 'movie'),
  popularTv('Popular shows', '/api/v1/discover/tv', 'tv'),
  upcomingMovies(
    'Coming to theaters',
    '/api/v1/discover/movies/upcoming',
    'movie',
  ),
  upcomingTv('Coming to TV', '/api/v1/discover/tv/upcoming', 'tv');

  const DiscoverFeed(this.label, this.path, [this.mediaType]);
  final String label;
  final String path;

  /// Set for feeds that hold one kind only, in case results omit it.
  final String? mediaType;
}

/// A request in Overseerr / Jellyseerr.
class MediaRequest {
  MediaRequest(this.raw, {this.title = '', this.posterPath, this.year});
  final Map<String, dynamic> raw;
  String title;
  String? posterPath;
  int? year;

  int get id => asInt(raw['id']);

  /// 1 pending, 2 approved, 3 declined.
  int get status => asInt(raw['status']);
  bool get isPending => status == 1;
  String get statusLabel => switch (status) {
    1 => 'Pending',
    2 => _mediaStatusLabel,
    3 => 'Declined',
    _ => 'Unknown',
  };

  /// Once approved, what's happened to the media itself.
  String get _mediaStatusLabel =>
      switch (asInt((raw['media'] as Map?)?['status'])) {
        3 => 'Processing',
        4 => 'Partly available',
        5 => 'Available',
        _ => 'Approved',
      };

  bool get isTv => raw['type'] == 'tv';
  int get tmdbId => asInt((raw['media'] as Map?)?['tmdbId']);
  String get requestedBy =>
      ((raw['requestedBy'] as Map?)?['displayName'] ?? '').toString();
  DateTime? get createdAt => parseDate(raw['createdAt']);
  String? get posterUrl =>
      posterPath == null ? null : '$tmdbImageBase$posterPath';
}

/// A search result from TMDB, through Overseerr.
class DiscoverResult {
  DiscoverResult(this.raw);
  final Map<String, dynamic> raw;

  int get tmdbId => asInt(raw['id']);
  String get mediaType => (raw['mediaType'] ?? '').toString();
  String get title => (raw['title'] ?? raw['name'] ?? '').toString();
  String get overview => (raw['overview'] ?? '').toString();
  String? get posterUrl =>
      raw['posterPath'] == null ? null : '$tmdbImageBase${raw['posterPath']}';
  String? get backdropUrl => raw['backdropPath'] == null
      ? null
      : '$tmdbBackdropBase${raw['backdropPath']}';
  bool get isTv => mediaType == 'tv';

  /// TMDB score out of 10, 0 when unrated.
  double get rating => asDouble(raw['voteAverage']);
  int? get year {
    final d = (raw['releaseDate'] ?? raw['firstAirDate'] ?? '').toString();
    return d.length >= 4 ? int.tryParse(d.substring(0, 4)) : null;
  }

  /// Overseerr media status: 1 unknown … 5 available.
  int get availability => asInt((raw['mediaInfo'] as Map?)?['status']);
  bool get canRequest =>
      availability < 2 && (mediaType == 'movie' || mediaType == 'tv');
  String get availabilityLabel => switch (availability) {
    2 => 'Requested',
    3 => 'Processing',
    4 => 'Partly available',
    5 => 'Available',
    _ => '',
  };
}

class OverseerrClient extends ServiceClient {
  OverseerrClient(super.server, {super.httpClient});

  @override
  Map<String, String> authHeaders() => {'X-Api-Key': server.apiKey};

  @override
  Future<void> test() async {
    await getJson('/api/v1/auth/me');
  }

  /// Recent requests with titles and posters filled in.
  Future<List<MediaRequest>> requests({String filter = 'all'}) async {
    final json = await getJson(
      '/api/v1/request',
      query: {'take': '30', 'skip': '0', 'sort': 'added', 'filter': filter},
    );
    final list = [
      for (final r in (json as Map)['results'] as List)
        MediaRequest((r as Map).cast()),
    ];
    await Future.wait(list.map(_fillDetails));
    return list;
  }

  Future<void> _fillDetails(MediaRequest r) async {
    try {
      final d = await getJson(
        '/api/v1/${r.isTv ? 'tv' : 'movie'}/${r.tmdbId}',
      ) as Map;
      r.title = (d['title'] ?? d['name'] ?? '').toString();
      r.posterPath = d['posterPath'] as String?;
      final date = (d['releaseDate'] ?? d['firstAirDate'] ?? '').toString();
      r.year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
    } on ApiException {
      r.title = 'TMDB #${r.tmdbId}';
    }
  }

  Future<void> approve(MediaRequest r) =>
      sendJson('POST', '/api/v1/request/${r.id}/approve');
  Future<void> decline(MediaRequest r) =>
      sendJson('POST', '/api/v1/request/${r.id}/decline');

  Future<List<DiscoverResult>> search(String query) async => parseResults(
    await getJson('/api/v1/search', query: {'query': query, 'page': '1'}),
  );

  /// One of the Discover lists (trending, popular…).
  Future<List<DiscoverResult>> discover(
    DiscoverFeed feed, {
    int page = 1,
  }) async => parseResults(
    await getJson(feed.path, query: {'page': '$page'}),
    mediaType: feed.mediaType,
  );

  /// Movies and shows from a search or Discover response; people and
  /// collections are dropped.
  static List<DiscoverResult> parseResults(Object? json, {String? mediaType}) {
    final results = json is Map ? json['results'] : null;
    if (results is! List) return [];
    return [
      for (final r in results)
        if (r is Map)
          DiscoverResult({
            'mediaType': ?mediaType,
            ...r.cast<String, dynamic>(),
          }),
    ].where((r) => r.mediaType == 'movie' || r.mediaType == 'tv').toList();
  }

  /// [r] with Overseerr's availability filled in (requested, available…),
  /// for titles that came from TMDB directly.
  Future<DiscoverResult> withStatus(DiscoverResult r) async {
    final d = await getJson('/api/v1/${r.isTv ? 'tv' : 'movie'}/${r.tmdbId}');
    final info = d is Map ? d['mediaInfo'] : null;
    return DiscoverResult({...r.raw, 'mediaInfo': ?info});
  }

  Future<void> submitRequest(DiscoverResult r) => sendJson(
    'POST',
    '/api/v1/request',
    json: {
      'mediaType': r.mediaType,
      'mediaId': r.tmdbId,
      if (r.mediaType == 'tv') 'seasons': 'all',
    },
  );
}

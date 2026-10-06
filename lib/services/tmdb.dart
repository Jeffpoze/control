import '../models/server.dart';
import 'overseerr.dart';
import 'service_client.dart';

export 'overseerr.dart' show DiscoverFeed, DiscoverResult;

/// The app's own TMDB key, put in at build time (`--dart-define=TMDB_KEY=…`
/// from a CI secret or a private file on the build Mac), so it's never in
/// the source. Empty in builds without it.
const builtInTmdbKey = String.fromEnvironment('TMDB_KEY');

/// TMDB with the built-in key, or null when the build has none.
final ServerConfig? builtInTmdb = builtInTmdbKey.isEmpty
    ? null
    : ServerConfig(
        id: 'tmdb.builtin',
        kind: ServiceKind.tmdb,
        name: 'TMDB',
        remoteUrl: TmdbClient.defaultUrl,
        apiKey: builtInTmdbKey,
      );

/// The Movie Database, for the trending banner and the popular and
/// upcoming rows. Uses the built-in key, or a user's own free key
/// (themoviedb.org, Settings → API): the short "API key" and the long "API
/// Read Access Token" both work.
class TmdbClient extends ServiceClient {
  TmdbClient(super.server, {super.httpClient});

  static const defaultUrl = 'https://api.themoviedb.org';

  String get _key => server.apiKey.trim();

  /// The read access token is a long JWT sent as a Bearer token; the short
  /// v3 key goes in the query instead.
  bool get _isToken => _key.length > 40;

  @override
  Map<String, String> authHeaders() =>
      _isToken ? {'Authorization': 'Bearer $_key'} : const {};

  Map<String, String> _query([Map<String, String> extra = const {}]) => {
    if (!_isToken) 'api_key': _key,
    ...extra,
  };

  @override
  Future<void> test() async {
    final json = await getJson('/3/configuration', query: _query());
    if (json is! Map || json['images'] == null) {
      throw ApiException('That address answered, but it isn\'t TMDB.');
    }
  }

  static String pathFor(DiscoverFeed feed) => switch (feed) {
    DiscoverFeed.trending => '/3/trending/all/day',
    DiscoverFeed.popularMovies => '/3/movie/popular',
    DiscoverFeed.popularTv => '/3/tv/popular',
    DiscoverFeed.upcomingMovies => '/3/movie/upcoming',
    DiscoverFeed.upcomingTv => '/3/tv/on_the_air',
  };

  Future<List<DiscoverResult>> discover(DiscoverFeed feed) async => parse(
    await getJson(pathFor(feed), query: _query({'page': '1'})),
    mediaType: feed.mediaType,
  );

  /// TMDB's snake_case results, in the shape Overseerr uses, so the banner
  /// and rows work the same from either source. People are dropped.
  static List<DiscoverResult> parse(Object? json, {String? mediaType}) {
    final results = json is Map ? json['results'] : null;
    if (results is! List) return [];
    return [
      for (final r in results)
        if (r is Map)
          DiscoverResult({
            'id': r['id'],
            'mediaType': r['media_type'] ?? mediaType,
            'title': r['title'],
            'name': r['name'],
            'overview': r['overview'],
            'posterPath': r['poster_path'],
            'backdropPath': r['backdrop_path'],
            'voteAverage': r['vote_average'],
            'releaseDate': r['release_date'],
            'firstAirDate': r['first_air_date'],
          }),
    ].where((r) => r.mediaType == 'movie' || r.mediaType == 'tv').toList();
  }
}

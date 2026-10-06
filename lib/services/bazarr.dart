import '../util/format.dart';
import 'service_client.dart';

/// A subtitle language Bazarr is missing or has fetched.
class SubLanguage {
  SubLanguage({
    required this.name,
    required this.code,
    this.hi = false,
    this.forced = false,
  });
  final String name;

  /// Two-letter code ("en"), what Bazarr's search endpoints take.
  final String code;
  final bool hi;
  final bool forced;

  String get label => [name, if (hi) 'HI', if (forced) 'Forced'].join(' · ');

  static SubLanguage? parse(Object? v) {
    if (v is! Map) return null;
    final code = (v['code2'] ?? v['code'] ?? '').toString();
    if (code.isEmpty) return null;
    return SubLanguage(
      name: (v['name'] ?? code).toString(),
      code: code,
      hi: v['hi'] == true,
      forced: v['forced'] == true,
    );
  }
}

/// An episode or movie with subtitles still to find.
class WantedSubtitle {
  WantedSubtitle({
    required this.title,
    required this.subtitle,
    required this.missing,
    required this.isMovie,
    this.seriesId = 0,
    this.episodeId = 0,
    this.movieId = 0,
  });
  final String title;
  final String subtitle;
  final List<SubLanguage> missing;
  final bool isMovie;
  final int seriesId;
  final int episodeId;
  final int movieId;
}

/// Something Bazarr did: downloaded, upgraded, deleted a subtitle…
class SubtitleEvent {
  SubtitleEvent({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.when,
    required this.isMovie,
  });
  final String title;
  final String subtitle;
  final String description;

  /// As Bazarr phrases it ("2 hours ago").
  final String when;
  final bool isMovie;
}

class BazarrClient extends ServiceClient {
  BazarrClient(super.server, {super.httpClient});

  @override
  Map<String, String> authHeaders() => {'X-API-KEY': server.apiKey};

  @override
  Future<void> test() async {
    final json = await getJson('/api/system/status');
    if (json is! Map || json['data'] is! Map) {
      throw ApiException('That address answered, but it isn\'t Bazarr.');
    }
  }

  Future<List<WantedSubtitle>> wantedEpisodes() async => parseWanted(
    await getJson(
      '/api/episodes/wanted',
      query: {'start': '0', 'length': '100'},
    ),
    movies: false,
  );

  Future<List<WantedSubtitle>> wantedMovies() async => parseWanted(
    await getJson('/api/movies/wanted', query: {'start': '0', 'length': '100'}),
    movies: true,
  );

  static List<WantedSubtitle> parseWanted(
    Object? json, {
    required bool movies,
  }) {
    final data = json is Map ? json['data'] : null;
    if (data is! List) return [];
    return [
      for (final m in data)
        if (m is Map)
          WantedSubtitle(
            isMovie: movies,
            title: ((movies ? m['title'] : m['seriesTitle']) ?? '').toString(),
            subtitle: movies
                ? (m['sceneName'] ?? '').toString()
                : [
                    m['episode_number'],
                    m['episodeTitle'],
                  ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
            missing: [
              for (final l in (m['missing_subtitles'] as List? ?? const []))
                ?SubLanguage.parse(l),
            ],
            seriesId: asInt(m['sonarrSeriesId']),
            episodeId: asInt(m['sonarrEpisodeId']),
            movieId: asInt(m['radarrId']),
          ),
    ];
  }

  Future<List<SubtitleEvent>> history() async {
    final results = await Future.wait([
      getJson('/api/episodes/history', query: {'start': '0', 'length': '25'}),
      getJson('/api/movies/history', query: {'start': '0', 'length': '25'}),
    ]);
    return [
      ...parseHistory(results[0], movies: false),
      ...parseHistory(results[1], movies: true),
    ];
  }

  static List<SubtitleEvent> parseHistory(
    Object? json, {
    required bool movies,
  }) {
    final data = json is Map ? json['data'] : null;
    if (data is! List) return [];
    return [
      for (final m in data)
        if (m is Map)
          SubtitleEvent(
            isMovie: movies,
            title: ((movies ? m['title'] : m['seriesTitle']) ?? '').toString(),
            subtitle: [
              if (!movies) m['episode_number'],
              SubLanguage.parse(m['language'])?.label,
            ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
            description: (m['description'] ?? '').toString(),
            when: (m['timestamp'] ?? '').toString(),
          ),
    ];
  }

  /// Searches the providers for one missing language and downloads the best.
  Future<void> searchMissing(WantedSubtitle w, SubLanguage lang) => request(
    'PATCH',
    w.isMovie ? '/api/movies/subtitles' : '/api/episodes/subtitles',
    query: {
      if (w.isMovie) 'radarrid': '${w.movieId}',
      if (!w.isMovie) ...{
        'seriesid': '${w.seriesId}',
        'episodeid': '${w.episodeId}',
      },
      'language': lang.code,
      'hi': '${lang.hi}',
      'forced': '${lang.forced}',
    },
  );

  /// Runs Bazarr's "search all wanted" tasks for series and movies.
  Future<void> searchAllWanted() async {
    for (final task in const [
      'wanted_search_missing_subtitles_series',
      'wanted_search_missing_subtitles_movies',
    ]) {
      await request('POST', '/api/system/tasks', query: {'taskid': task});
    }
  }
}

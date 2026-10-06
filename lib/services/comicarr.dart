import '../util/format.dart';
import 'service_client.dart';

/// A series in the Comicarr library.
class ComicSeries {
  ComicSeries(this.raw, {this.coverUrl});
  final Map<String, dynamic> raw;

  /// The provider's cover (ComicVine, Metron), or Comicarr's cached copy.
  final String? coverUrl;

  String get id => (raw['ComicID'] ?? '').toString();
  String get name => (raw['ComicName'] ?? '').toString();
  String get year => (raw['ComicYear'] ?? '').toString();
  String get publisher => (raw['ComicPublisher'] ?? '').toString();

  /// "Active", "Paused", "Loading"…
  String get status => (raw['Status'] ?? '').toString();
  bool get paused => status.toLowerCase() == 'paused';
  int get have => asInt(raw['Have']);
  int get total => asInt(raw['Total']);
  String get latestIssue => (raw['LatestIssue'] ?? '').toString();
  String get latestDate => (raw['LatestDate'] ?? '').toString();
  String get description => (raw['Description'] ?? '').toString();
  double get completion =>
      total > 0 ? (have / total).clamp(0, 1).toDouble() : 0;
}

/// An issue of a series, with Comicarr's display state.
class ComicIssue {
  ComicIssue(this.raw);
  final Map<String, dynamic> raw;

  String get id => (raw['id'] ?? raw['IssueID'] ?? '').toString();
  String get number => (raw['number'] ?? raw['Issue_Number'] ?? '').toString();
  String get name => (raw['name'] ?? raw['IssueName'] ?? '').toString();
  String get releaseDate =>
      (raw['releaseDate'] ?? raw['ReleaseDate'] ?? raw['issueDate'] ?? '')
          .toString();

  /// "Downloaded", "Wanted", "Snatched", "Skipped", "Missing"…
  String get state =>
      (raw['displayState'] ?? raw['legacyStatus'] ?? raw['status'] ?? '')
          .toString();
  bool get owned =>
      raw['owned'] == true ||
      state == 'Downloaded' ||
      state == 'Archived';
}

/// A wanted or upcoming issue, with its series name.
class ComicRelease {
  ComicRelease({
    required this.seriesId,
    required this.issueId,
    required this.series,
    required this.number,
    this.name = '',
    this.date = '',
    this.status = '',
  });
  final String seriesId;
  final String issueId;
  final String series;
  final String number;
  final String name;
  final String date;
  final String status;

  String get label => number.isEmpty ? series : '$series #$number';
}

/// A ComicVine or Metron search result, to add to the library.
class ComicSearchResult {
  ComicSearchResult(this.raw);
  final Map<String, dynamic> raw;

  String get id => (raw['comicid'] ?? '').toString();
  String get name => (raw['name'] ?? '').toString();
  String get year => (raw['comicyear'] ?? '').toString();
  String get publisher => (raw['publisher'] ?? '').toString();
  int get issues => asInt(raw['issues']);
  String? get coverUrl {
    final u = (raw['comicthumb'] ?? raw['comicimage'] ?? '').toString();
    return u.startsWith('http') ? u : null;
  }

  bool get inLibrary => raw['in_library'] == true;
}

/// Comicarr (the Mylar3 successor). Its API key only opens a few read-only
/// routes, so Control signs in with the username and password like the web
/// app and keeps the session cookie. Every change also needs the
/// `X-Requested-With: ComicarrFrontend` header.
class ComicarrClient extends ServiceClient {
  ComicarrClient(super.server, {super.httpClient});

  static const _cookieName = 'comicarr_session';
  String? _cookie;

  @override
  Map<String, String> authHeaders() => {
    'X-Requested-With': 'ComicarrFrontend',
    if (_cookie != null) 'Cookie': '$_cookieName=$_cookie',
  };

  /// Headers for loading Comicarr's own cached covers.
  Map<String, String> get imageHeaders => {
    if (_cookie != null) 'Cookie': '$_cookieName=$_cookie',
  };

  Future<void> _login() async {
    final res = await request(
      'POST',
      '/api/auth/login',
      json: {'username': server.username, 'password': server.password},
      checkStatus: false,
    );
    if (res.statusCode == 200) {
      final cookie = parseSessionCookie(res.headers['set-cookie']);
      if (cookie == null) {
        throw ApiException('Comicarr signed in but didn\'t return a session.');
      }
      _cookie = cookie;
      return;
    }
    var message = 'Comicarr rejected the username or password.';
    try {
      final body = ServiceClient.decode(res);
      if (body is Map && body['error'] is String) {
        message = 'Comicarr: ${body['error']}';
      } else if (body is Map && body['detail'] is String) {
        message = 'Comicarr: ${body['detail']}';
      }
    } on ApiException {
      // Not JSON: keep the generic message.
    }
    throw ApiException(message, statusCode: res.statusCode);
  }

  static String? parseSessionCookie(String? setCookie) {
    if (setCookie == null) return null;
    return RegExp('$_cookieName=([^;,]+)').firstMatch(setCookie)?[1];
  }

  /// Signs in first if needed, and once more if the session has expired.
  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? json,
  }) async {
    if (_cookie == null) await _login();
    try {
      return await sendJson(method, path, json: json, query: query);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      _cookie = null;
      await _login();
      return sendJson(method, path, json: json, query: query);
    }
  }

  @override
  Future<void> test() async {
    final health = await getJson('/api/health');
    if (health is! Map || health['status'] != 'ok') {
      throw ApiException('That address answered, but it isn\'t Comicarr.');
    }
    _cookie = null;
    await _login();
  }

  Uri? get _base => activeBase ?? server.baseUris.firstOrNull;

  Future<List<ComicSeries>> series() async {
    final json = await _call('GET', '/api/series');
    return parseSeries(json, _base);
  }

  static List<ComicSeries> parseSeries(Object? json, Uri? base) {
    final list = json is List
        ? json
        : json is Map
        ? (json['comics'] as List? ?? const [])
        : const [];
    return [
      for (final m in list)
        if (m is Map) _toSeries(m.cast(), base),
    ];
  }

  static ComicSeries _toSeries(Map<String, dynamic> m, Uri? base) {
    final provider = (m['ComicImageURL'] ?? '').toString();
    final own = (m['ComicImage'] ?? '').toString();
    String? cover;
    if (provider.startsWith('http')) {
      cover = provider;
    } else if (own.startsWith('http')) {
      cover = own;
    } else if (own.startsWith('/') && base != null) {
      cover = joinUri(base, own).toString();
    }
    return ComicSeries(m, coverUrl: cover);
  }

  /// The series and its issues, newest first.
  Future<(ComicSeries, List<ComicIssue>)> seriesDetail(String id) async {
    final json = await _call('GET', '/api/series/$id') as Map;
    return parseDetail(json, _base);
  }

  static (ComicSeries, List<ComicIssue>) parseDetail(Map json, Uri? base) {
    final comic = json['comic'];
    final first = comic is List && comic.isNotEmpty
        ? (comic.first as Map).cast<String, dynamic>()
        : comic is Map
        ? comic.cast<String, dynamic>()
        : <String, dynamic>{};
    return (
      _toSeries(first, base),
      [
        for (final i in (json['issues'] as List? ?? const []))
          if (i is Map) ComicIssue(i.cast()),
      ],
    );
  }

  Future<List<ComicRelease>> wanted() async =>
      parseWanted(await _call('GET', '/api/wanted', query: {'limit': '200'}));

  static List<ComicRelease> parseWanted(Object? json) {
    final list = json is Map ? (json['issues'] as List? ?? const []) : const [];
    return [
      for (final m in list)
        if (m is Map)
          ComicRelease(
            seriesId: (m['ComicID'] ?? '').toString(),
            issueId: (m['IssueID'] ?? '').toString(),
            series: (m['ComicName'] ?? '').toString(),
            number: (m['Issue_Number'] ?? '').toString(),
            name: (m['IssueName'] ?? '').toString(),
            date: (m['ReleaseDate'] ?? m['IssueDate'] ?? '').toString(),
            status: (m['Status'] ?? 'Wanted').toString(),
          ),
    ];
  }

  /// This week's releases for series in the library.
  Future<List<ComicRelease>> thisWeek() async => parseUpcoming(
    await _call(
      'GET',
      '/api/upcoming',
      query: {'include_downloaded_issues': 'true'},
    ),
  );

  static List<ComicRelease> parseUpcoming(Object? json) => [
    for (final m in json is List ? json : const [])
      if (m is Map)
        ComicRelease(
          seriesId: (m['ComicID'] ?? '').toString(),
          issueId: (m['IssueID'] ?? '').toString(),
          series: (m['DisplayComicName'] ?? m['ComicName'] ?? '').toString(),
          number: (m['IssueNumber'] ?? '').toString(),
          date: (m['IssueDate'] ?? '').toString(),
          status: (m['Status'] ?? '').toString(),
        ),
  ];

  /// Marks an issue wanted and starts a search for it.
  Future<void> searchIssue(String issueId) =>
      _call('PUT', '/api/series/issues/$issueId/queue');

  /// Marks an issue skipped.
  Future<void> skipIssue(String issueId) =>
      _call('PUT', '/api/series/issues/$issueId/unqueue');

  /// Searches every missing issue of a series. Comicarr asks for a preview
  /// first and a confirmation with its token; returns how many it queued.
  Future<int> searchMissing(String seriesId) async {
    final preview =
        await _call('GET', '/api/series/$seriesId/search-missing/preview')
            as Map;
    final eligible = asInt(preview['eligibleCount']);
    if (eligible == 0 || preview['preview_token'] == null) return 0;
    await _call(
      'POST',
      '/api/series/$seriesId/search-missing',
      json: {
        'confirm': true,
        'preview_token': preview['preview_token'],
        'fingerprint': preview['fingerprint'],
      },
    );
    return eligible;
  }

  Future<void> refresh(String seriesId) =>
      _call('POST', '/api/series/$seriesId/refresh');

  Future<void> setPaused(String seriesId, bool paused) =>
      _call('PUT', '/api/series/$seriesId/${paused ? 'pause' : 'resume'}');

  Future<List<ComicSearchResult>> search(String name) async {
    try {
      final json = await _call(
        'POST',
        '/api/search/comics',
        json: {'name': name, 'limit': 30},
      );
      final list = json is Map ? json['results'] as List? ?? const [] : const [];
      return [
        for (final r in list)
          if (r is Map) ComicSearchResult(r.cast()),
      ];
    } on ApiException catch (e) {
      // Comicarr answers "no results" with a 400.
      if (e.statusCode == 400) return [];
      rethrow;
    }
  }

  /// Adds a series; Comicarr imports it in the background.
  Future<void> add(ComicSearchResult r) =>
      _call('POST', '/api/search/add', json: {'id': r.id});
}

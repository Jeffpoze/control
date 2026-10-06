import '../util/format.dart';
import 'service_client.dart';

/// One release found across Prowlarr's indexers.
class Release {
  Release(this.raw);
  final Map<String, dynamic> raw;

  String get guid => raw['guid'].toString();
  int get indexerId => asInt(raw['indexerId']);
  String get indexer => (raw['indexer'] ?? '').toString();
  String get title => (raw['title'] ?? '').toString();
  int get size => asInt(raw['size']);
  bool get isTorrent => raw['protocol'] == 'torrent';
  int? get seeders => raw['seeders'] == null ? null : asInt(raw['seeders']);
  int? get leechers => raw['leechers'] == null ? null : asInt(raw['leechers']);
  int get grabs => asInt(raw['grabs']);
  DateTime? get published => parseDate(raw['publishDate']);
  int get ageDays => asInt(raw['age']);
  String? get infoUrl => raw['infoUrl'] as String?;
  String? get downloadUrl => (raw['magnetUrl'] as String?)?.isNotEmpty == true
      ? raw['magnetUrl'] as String
      : raw['downloadUrl'] as String?;
}

class Indexer {
  Indexer(this.id, this.name, this.enabled, this.protocol);
  final int id;
  final String name;
  final bool enabled;
  final String protocol;
}

/// Prowlarr: search every indexer at once and send a release to a client.
class ProwlarrClient extends ServiceClient {
  ProwlarrClient(super.server, {super.httpClient});

  @override
  Map<String, String> authHeaders() => {'X-Api-Key': server.apiKey};

  @override
  Future<void> test() async {
    final status = await getJson('/api/v1/system/status');
    if (status is! Map || status['version'] == null) {
      throw ApiException('That address answered, but it isn\'t Prowlarr.');
    }
  }

  Future<List<Indexer>> indexers() async {
    final list = await getJson('/api/v1/indexer') as List;
    return [
      for (final i in list)
        Indexer(
          asInt((i as Map)['id']),
          (i['name'] ?? '').toString(),
          i['enable'] == true,
          (i['protocol'] ?? '').toString(),
        ),
    ];
  }

  Future<List<Release>> search(String query, {List<int>? indexerIds}) async {
    final list = await getJson(
      '/api/v1/search',
      query: {
        'query': query,
        'type': 'search',
        'limit': '100',
        if (indexerIds != null && indexerIds.isNotEmpty)
          'indexerIds': [for (final i in indexerIds) '$i'],
      },
    ) as List;
    return _sorted(list);
  }

  List<Release> _sorted(List list) {
    final releases = [for (final r in list) Release((r as Map).cast())];
    releases.sort((a, b) {
      final s = (b.seeders ?? b.grabs).compareTo(a.seeders ?? a.grabs);
      return s != 0 ? s : a.ageDays.compareTo(b.ageDays);
    });
    return releases;
  }

  /// Sends the release to Prowlarr's own download client.
  Future<void> grab(Release r) => sendJson(
    'POST',
    '/api/v1/search',
    json: {'guid': r.guid, 'indexerId': r.indexerId},
  );
}

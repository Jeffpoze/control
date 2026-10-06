import '../models/server.dart';
import '../util/format.dart';
import 'service_client.dart';
import 'streaming.dart';

export 'streaming.dart';

/// Emby and Jellyfin share an API (Jellyfin is a fork of Emby): sessions,
/// system info and item images all live at the same paths.
class MediaServerClient extends ServiceClient implements StreamingClient {
  MediaServerClient(super.server, {super.httpClient});

  bool get isJellyfin => server.kind == ServiceKind.jellyfin;

  /// Jellyfin 10.11 can turn off the old X-Emby-Token header, so it gets the
  /// standard Authorization one, unless proxy basic auth already uses it.
  @override
  Map<String, String> authHeaders() => isJellyfin && server.proxyUser.isEmpty
      ? {'Authorization': 'MediaBrowser Token="${server.apiKey}"'}
      : {'X-Emby-Token': server.apiKey};

  @override
  Future<void> test() async {
    final info = await getJson('/System/Info');
    if (info is! Map || info['Version'] == null) {
      throw ApiException(
        'That address answered, but it isn\'t ${server.kind.label}.',
      );
    }
  }

  @override
  Future<Activity> activity() async {
    final json = await getJson(
      '/Sessions',
      query: {'ActiveWithinSeconds': '960'},
    );
    return Activity(
      parseSessions(json, activeBase ?? server.baseUris.firstOrNull),
    );
  }

  /// Sessions that are playing something. [base] is used to build artwork
  /// URLs (item images don't need the API key).
  static List<PlaySession> parseSessions(Object? json, Uri? base) {
    if (json is! List) return [];
    final out = <PlaySession>[];
    for (final s in json) {
      if (s is! Map) continue;
      final item = (s['NowPlayingItem'] as Map?)?.cast<String, dynamic>();
      if (item == null) continue;
      final play = (s['PlayState'] as Map?)?.cast<String, dynamic>() ?? {};
      final type = item['Type'];
      final String title;
      final String subtitle;
      String? imageId;
      String? imageTag;
      switch (type) {
        case 'Episode':
          final season = asInt(item['ParentIndexNumber']);
          final ep = asInt(item['IndexNumber']);
          title = (item['SeriesName'] ?? '').toString();
          subtitle =
              'S${season.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')} · ${item['Name'] ?? ''}';
          imageId = item['SeriesId']?.toString();
          imageTag = item['SeriesPrimaryImageTag']?.toString();
        case 'Audio':
          final artists = (item['Artists'] as List?)?.join(', ') ?? '';
          title = (item['AlbumArtist'] ?? artists).toString();
          subtitle = (item['Name'] ?? '').toString();
          imageId = item['AlbumId']?.toString();
          imageTag = item['AlbumPrimaryImageTag']?.toString();
        default:
          title = (item['Name'] ?? '').toString();
          final year = asInt(item['ProductionYear']);
          subtitle = year > 0 ? '$year' : '';
      }
      if (imageId == null || imageTag == null) {
        imageId = item['Id']?.toString();
        imageTag = ((item['ImageTags'] as Map?)?['Primary'])?.toString();
      }
      final runtime = asDouble(item['RunTimeTicks']);
      final position = asDouble(play['PositionTicks']);
      final transcode = (s['TranscodingInfo'] as Map?)?.cast<String, dynamic>();
      final bitrate = asInt(transcode?['Bitrate']);
      out.add(
        PlaySession(
          id: (s['Id'] ?? '').toString(),
          title: title,
          subtitle: subtitle,
          user: (s['UserName'] ?? '').toString(),
          player: [
            s['Client'],
            s['DeviceName'],
          ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
          progress: runtime > 0
              ? (position / runtime).clamp(0, 1).toDouble()
              : 0,
          state: play['IsPaused'] == true ? 'paused' : 'playing',
          transcoding: play['PlayMethod'] == 'Transcode',
          quality: bitrate > 0
              ? '${(bitrate / 1000000).toStringAsFixed(1)} Mbps'
              : '',
          thumbUrl: base == null || imageId == null
              ? null
              : joinUri(base, '/Items/$imageId/Images/Primary', {
                  'maxHeight': '300',
                  'tag': ?imageTag,
                }).toString(),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> terminate(PlaySession s, {String message = ''}) async {
    if (message.isNotEmpty) {
      await request(
        'POST',
        '/Sessions/${s.id}/Message',
        json: {'Header': 'Control', 'Text': message, 'TimeoutMs': 8000},
      );
    }
    await request('POST', '/Sessions/${s.id}/Playing/Stop');
  }
}

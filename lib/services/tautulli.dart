import '../util/format.dart';
import 'service_client.dart';
import 'streaming.dart';

export 'streaming.dart';

class TautulliClient extends ServiceClient implements StreamingClient {
  TautulliClient(super.server, {super.httpClient});

  Future<dynamic> _cmd(
    String cmd, [
    Map<String, String> params = const {},
  ]) async {
    final json = await getJson(
      '/api/v2',
      query: {'apikey': server.apiKey, 'cmd': cmd, ...params},
    );
    final response = (json as Map)['response'] as Map;
    if (response['result'] != 'success') {
      throw ApiException(
        'Tautulli: ${response['message'] ?? 'request failed'}',
      );
    }
    return response['data'];
  }

  @override
  Future<void> test() => _cmd('get_server_friendly_name');

  @override
  Future<Activity> activity() async {
    final data = (await _cmd('get_activity') as Map).cast<String, dynamic>();
    final sessions = [
      for (final s in (data['sessions'] as List? ?? const []))
        if (s is Map) parseSession(s.cast(), _imageProxy),
    ];
    return Activity(sessions, bandwidthKbps: asInt(data['total_bandwidth']));
  }

  /// One Tautulli session; [image] turns a Plex thumb path into a URL.
  static PlaySession parseSession(
    Map<String, dynamic> m,
    String? Function(String path) image,
  ) {
    final type = m['media_type'];
    final grandparentThumb = (m['grandparent_thumb'] ?? '').toString();
    final thumb = grandparentThumb.isNotEmpty
        ? grandparentThumb
        : (m['thumb'] ?? '').toString();
    final String title;
    final String subtitle;
    if (type == 'episode') {
      final s = asInt(m['parent_media_index']);
      final e = asInt(m['media_index']);
      title = (m['grandparent_title'] ?? '').toString();
      subtitle =
          'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')} · ${m['title']}';
    } else if (type == 'track') {
      title = (m['grandparent_title'] ?? '').toString();
      subtitle = (m['title'] ?? '').toString();
    } else {
      title = (m['title'] ?? m['full_title'] ?? '').toString();
      subtitle = m['year']?.toString() ?? '';
    }
    return PlaySession(
      id: '${m['session_key']}',
      title: title,
      subtitle: subtitle,
      user: (m['friendly_name'] ?? m['user'] ?? '').toString(),
      player: (m['player'] ?? m['platform'] ?? '').toString(),
      progress: (asDouble(m['progress_percent']) / 100).clamp(0, 1).toDouble(),
      state: (m['state'] ?? '').toString(),
      transcoding: m['transcode_decision'] == 'transcode',
      quality: (m['quality_profile'] ?? '').toString(),
      thumbUrl: thumb.isEmpty ? null : image(thumb),
    );
  }

  String? _imageProxy(String path) {
    final base = activeBase ?? server.baseUris.firstOrNull;
    if (base == null) return null;
    return joinUri(base, '/api/v2', {
      'apikey': server.apiKey,
      'cmd': 'pms_image_proxy',
      'img': path,
      'width': '300',
      'fallback': 'poster',
    }).toString();
  }

  @override
  Future<void> terminate(PlaySession s, {String message = ''}) => _cmd(
    'terminate_session',
    {'session_key': s.id, if (message.isNotEmpty) 'message': message},
  );
}

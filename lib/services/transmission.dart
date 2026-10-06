import '../util/format.dart';
import 'download_client.dart';
import 'service_client.dart';

/// Transmission, through its RPC (`/transmission/rpc`). Handles the
/// X-Transmission-Session-Id handshake (a 409 hands out the id).
class TransmissionClient extends DownloadClient {
  TransmissionClient(super.server, {super.httpClient});

  @override
  bool get hasHistory => false;
  @override
  bool get canDeleteData => true;

  String? _sessionId;

  @override
  Map<String, String> authHeaders() => {
    if (server.username.isNotEmpty || server.password.isNotEmpty)
      'Authorization': basicAuth(server.username, server.password),
    'X-Transmission-Session-Id': ?_sessionId,
  };

  /// The RPC path, unless the configured address already ends in it.
  String get _path {
    final base = server.baseUris.first.path;
    return base.endsWith('/rpc') ? '' : '/transmission/rpc';
  }

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final body = {'method': method, 'arguments': args};
    var res = await request('POST', _path, json: body, checkStatus: false);
    if (res.statusCode == 409) {
      _sessionId = res.headers['x-transmission-session-id'];
      res = await request('POST', _path, json: body, checkStatus: false);
    }
    if (res.statusCode == 401) {
      throw ApiException(
        'Transmission rejected the username or password.',
        statusCode: 401,
      );
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        'Transmission returned an error (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    final json = (ServiceClient.decode(res) as Map).cast<String, dynamic>();
    if (json['result'] != 'success') {
      throw ApiException('Transmission: ${json['result']}');
    }
    return ((json['arguments'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  static const _fields = [
    'id',
    'hashString',
    'name',
    'status',
    'percentDone',
    'sizeWhenDone',
    'leftUntilDone',
    'rateDownload',
    'rateUpload',
    'eta',
    'error',
    'errorString',
    'uploadRatio',
    'labels',
    'addedDate',
  ];

  @override
  Future<DownloadSnapshot> snapshot() async {
    final results = await Future.wait([
      rpc('torrent-get', {'fields': _fields}),
      rpc('session-stats'),
    ]);
    final torrents = [
      for (final t in results[0]['torrents'] as List)
        parseTorrent((t as Map).cast()),
    ];
    torrents.sort((a, b) => b.id.compareTo(a.id));
    return DownloadSnapshot(
      items: torrents,
      downSpeed: asInt(results[1]['downloadSpeed']),
      upSpeed: asInt(results[1]['uploadSpeed']),
    );
  }

  static DownloadItem parseTorrent(Map<String, dynamic> t) {
    final status = asInt(t['status']);
    final error = asInt(t['error']);
    final done = asDouble(t['percentDone']);
    final state = error != 0
        ? DownloadState.error
        : switch (status) {
            0 => done >= 1 ? DownloadState.completed : DownloadState.paused,
            1 || 2 => DownloadState.checking,
            3 || 5 => DownloadState.queued,
            4 => DownloadState.downloading,
            6 => DownloadState.seeding,
            _ => DownloadState.queued,
          };
    final eta = asInt(t['eta']);
    final labels = (t['labels'] as List?)?.cast<Object>() ?? const [];
    return DownloadItem(
      // Zero-padded so string sort matches add order.
      id: asInt(t['id']).toString().padLeft(8, '0'),
      name: (t['name'] ?? '').toString(),
      state: state,
      statusText: error != 0 ? t['errorString']?.toString() : null,
      progress: done.clamp(0, 1).toDouble(),
      sizeBytes: asInt(t['sizeWhenDone']),
      remainingBytes: asInt(t['leftUntilDone']),
      downSpeed: asInt(t['rateDownload']),
      upSpeed: asInt(t['rateUpload']),
      eta: eta > 0 && state == DownloadState.downloading
          ? Duration(seconds: eta)
          : null,
      category: labels.isEmpty ? null : labels.first.toString(),
      ratio: asDouble(t['uploadRatio']),
    );
  }

  int _id(DownloadItem item) => int.parse(item.id);

  @override
  Future<void> pauseAll() => rpc('torrent-stop');
  @override
  Future<void> resumeAll() => rpc('torrent-start');
  @override
  Future<void> pause(DownloadItem item) => rpc('torrent-stop', {
    'ids': [_id(item)],
  });
  @override
  Future<void> resume(DownloadItem item) => rpc('torrent-start', {
    'ids': [_id(item)],
  });
  @override
  Future<void> remove(DownloadItem item, {bool deleteData = false}) =>
      rpc('torrent-remove', {
        'ids': [_id(item)],
        'delete-local-data': deleteData,
      });

  @override
  Future<void> addUrl(String url, {String? category}) async {
    final res = await rpc('torrent-add', {
      'filename': url,
      if (category != null && category.isNotEmpty) 'labels': [category],
    });
    if (res.containsKey('torrent-duplicate')) {
      throw ApiException('Transmission already has that torrent.');
    }
  }
}

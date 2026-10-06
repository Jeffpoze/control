import '../util/format.dart';
import 'download_client.dart';
import 'service_client.dart';

/// SABnzbd, through its `/api?mode=…&output=json` API.
class SabnzbdClient extends DownloadClient {
  SabnzbdClient(super.server, {super.httpClient});

  @override
  bool get hasHistory => true;
  @override
  bool get canDeleteData => false;

  Future<Map<String, dynamic>> _api(
    String mode, [
    Map<String, String> params = const {},
  ]) async {
    final json = await getJson(
      '/api',
      query: {
        'mode': mode,
        'output': 'json',
        'apikey': server.apiKey,
        ...params,
      },
    );
    if (json is Map && json['status'] == false) {
      final error = json['error']?.toString() ?? 'Unknown error';
      throw ApiException(
        error.toLowerCase().contains('api key')
            ? 'SABnzbd rejected the API key.'
            : 'SABnzbd: $error',
      );
    }
    return (json as Map).cast<String, dynamic>();
  }

  @override
  Future<DownloadSnapshot> snapshot() async =>
      parseQueue(await _api('queue', {'limit': '200'}));

  static DownloadSnapshot parseQueue(Map<String, dynamic> json) {
    final q = (json['queue'] as Map).cast<String, dynamic>();
    final paused = q['paused'] == true;
    final speed = (asDouble(q['kbpersec']) * 1024).round();
    // SABnzbd reports one overall speed; it goes to the first active slot.
    var speedGiven = false;
    final items = <DownloadItem>[];
    for (final s in (q['slots'] as List? ?? const [])) {
      final slot = (s as Map).cast<String, dynamic>();
      final status = (slot['status'] ?? '').toString();
      final state = switch (status.toLowerCase()) {
        'downloading' ||
        'fetching' ||
        'grabbing' => paused ? DownloadState.paused : DownloadState.downloading,
        'paused' => DownloadState.paused,
        'checking' ||
        'quickcheck' ||
        'verifying' ||
        'repairing' => DownloadState.checking,
        'extracting' || 'moving' || 'running' => DownloadState.processing,
        'failed' => DownloadState.error,
        _ => paused ? DownloadState.paused : DownloadState.queued,
      };
      final active = state == DownloadState.downloading;
      items.add(
        DownloadItem(
          id: slot['nzo_id'].toString(),
          name: (slot['filename'] ?? '').toString(),
          state: state,
          statusText: status,
          progress: (asDouble(slot['percentage']) / 100).clamp(0, 1).toDouble(),
          sizeBytes: (asDouble(slot['mb']) * 1024 * 1024).round(),
          remainingBytes: (asDouble(slot['mbleft']) * 1024 * 1024).round(),
          downSpeed: active && !speedGiven ? speed : 0,
          eta: active ? parseClockDuration(slot['timeleft']?.toString()) : null,
          category: _cat(slot['cat']),
        ),
      );
      if (active) speedGiven = true;
    }
    return DownloadSnapshot(
      items: items,
      downSpeed: speed,
      paused: paused,
      remainingBytes: (asDouble(q['mbleft']) * 1024 * 1024).round(),
      freeSpaceBytes: (asDouble(q['diskspace1']) * 1024 * 1024 * 1024).round(),
    );
  }

  static String? _cat(Object? c) {
    final s = c?.toString();
    return (s == null || s == '*' || s.isEmpty) ? null : s;
  }

  @override
  Future<List<HistoryItem>> history() async {
    final json = await _api('history', {'limit': '100'});
    return parseHistory(json);
  }

  static List<HistoryItem> parseHistory(Map<String, dynamic> json) {
    final h = (json['history'] as Map).cast<String, dynamic>();
    return [
      for (final s in (h['slots'] as List? ?? const []))
        () {
          final slot = (s as Map).cast<String, dynamic>();
          final status = (slot['status'] ?? '').toString();
          final completed = asInt(slot['completed']);
          return HistoryItem(
            id: slot['nzo_id'].toString(),
            name: (slot['name'] ?? '').toString(),
            succeeded: status.toLowerCase() == 'completed',
            statusText: status,
            sizeBytes: asInt(slot['bytes']),
            completedAt: completed > 0
                ? DateTime.fromMillisecondsSinceEpoch(completed * 1000)
                : null,
            category: _cat(slot['category']),
            failMessage: (slot['fail_message'] as String?)?.isEmpty ?? true
                ? null
                : slot['fail_message'] as String,
          );
        }(),
    ];
  }

  @override
  Future<void> pauseAll() => _api('pause');
  @override
  Future<void> resumeAll() => _api('resume');
  @override
  Future<void> pause(DownloadItem item) =>
      _api('queue', {'name': 'pause', 'value': item.id});
  @override
  Future<void> resume(DownloadItem item) =>
      _api('queue', {'name': 'resume', 'value': item.id});
  @override
  Future<void> remove(DownloadItem item, {bool deleteData = false}) =>
      _api('queue', {'name': 'delete', 'value': item.id, 'del_files': '1'});
  @override
  Future<void> removeHistory(HistoryItem item) =>
      _api('history', {'name': 'delete', 'value': item.id});

  @override
  Future<void> addUrl(String url, {String? category}) => _api('addurl', {
    'name': url,
    if (category != null && category.isNotEmpty) 'cat': category,
  });
}

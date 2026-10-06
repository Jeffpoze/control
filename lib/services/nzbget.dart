import '../util/format.dart';
import 'download_client.dart';
import 'service_client.dart';

/// NZBGet, through its JSON-RPC API (`/jsonrpc`).
class NzbgetClient extends DownloadClient {
  NzbgetClient(super.server, {super.httpClient});

  @override
  bool get hasHistory => true;
  @override
  bool get canDeleteData => false;

  var _id = 0;

  @override
  Map<String, String> authHeaders() => {
    if (server.username.isNotEmpty || server.password.isNotEmpty)
      'Authorization': basicAuth(server.username, server.password),
  };

  Future<dynamic> call(String method, [List<Object?> params = const []]) async {
    final json = await sendJson(
      'POST',
      '/jsonrpc',
      json: {'jsonrpc': '2.0', 'method': method, 'params': params, 'id': ++_id},
    );
    if (json is Map && json['error'] != null) {
      final e = json['error'];
      throw ApiException(
        'NZBGet: ${e is Map ? e['message'] ?? e.toString() : e.toString()}',
      );
    }
    return (json as Map)['result'];
  }

  @override
  Future<DownloadSnapshot> snapshot() async {
    final results = await Future.wait([
      call('status'),
      call('listgroups', [0]),
    ]);
    return parse(
      (results[0] as Map).cast<String, dynamic>(),
      (results[1] as List).cast<Map>(),
    );
  }

  static DownloadSnapshot parse(Map<String, dynamic> status, List<Map> groups) {
    final paused = status['DownloadPaused'] == true;
    final speed = asInt(status['DownloadRate']);
    var speedGiven = false;
    final items = <DownloadItem>[];
    for (final g in groups) {
      final group = g.cast<String, dynamic>();
      final raw = (group['Status'] ?? '').toString();
      final sizeMb = asDouble(group['FileSizeMB']);
      final leftMb = asDouble(group['RemainingSizeMB']);
      final pausedMb = asDouble(group['PausedSizeMB']);
      final state = switch (raw) {
        'DOWNLOADING' =>
          paused ? DownloadState.paused : DownloadState.downloading,
        'PAUSED' => DownloadState.paused,
        'QUEUED' ||
        'FETCHING' => paused ? DownloadState.paused : DownloadState.queued,
        'PP_QUEUED' ||
        'LOADING_PARS' ||
        'VERIFYING_SOURCES' ||
        'REPAIRING' ||
        'VERIFYING_REPAIRED' => DownloadState.checking,
        'RENAMING' ||
        'UNPACKING' ||
        'MOVING' ||
        'EXECUTING_SCRIPT' ||
        'PP_FINISHED' => DownloadState.processing,
        _ => DownloadState.queued,
      };
      final active = state == DownloadState.downloading;
      final itemSpeed = active && !speedGiven ? speed : 0;
      if (active) speedGiven = true;
      final leftBytes = (leftMb * 1024 * 1024).round();
      items.add(
        DownloadItem(
          id: group['NZBID'].toString(),
          name: (group['NZBName'] ?? '').toString(),
          state: state,
          statusText: _titleCase(raw),
          progress: sizeMb > 0
              ? ((sizeMb - leftMb) / sizeMb).clamp(0, 1).toDouble()
              : 0,
          sizeBytes: (sizeMb * 1024 * 1024).round(),
          remainingBytes: leftBytes,
          downSpeed: itemSpeed,
          eta: itemSpeed > 0
              ? Duration(
                  seconds: ((leftMb - pausedMb) * 1024 * 1024 / itemSpeed)
                      .round(),
                )
              : null,
          category: (group['Category'] as String?)?.isEmpty ?? true
              ? null
              : group['Category'] as String,
        ),
      );
    }
    return DownloadSnapshot(
      items: items,
      downSpeed: speed,
      paused: paused,
      remainingBytes: (asDouble(status['RemainingSizeMB']) * 1024 * 1024)
          .round(),
      freeSpaceBytes: (asDouble(status['FreeDiskSpaceMB']) * 1024 * 1024)
          .round(),
    );
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Future<List<HistoryItem>> history() async {
    final list = (await call('history', [false]) as List).cast<Map>();
    return [
      for (final h in list.take(100))
        () {
          final item = h.cast<String, dynamic>();
          final status = (item['Status'] ?? '').toString();
          final t = asInt(item['HistoryTime']);
          return HistoryItem(
            id: item['NZBID'].toString(),
            name: (item['Name'] ?? item['NZBName'] ?? '').toString(),
            succeeded: status.startsWith('SUCCESS'),
            statusText: status.split('/').first.toLowerCase(),
            sizeBytes: (asDouble(item['FileSizeMB']) * 1024 * 1024).round(),
            completedAt: t > 0
                ? DateTime.fromMillisecondsSinceEpoch(t * 1000)
                : null,
            category: item['Category'] as String?,
          );
        }(),
    ];
  }

  Future<void> _edit(String command, String id) async {
    final ok = await call('editqueue', [
      command,
      '',
      [int.parse(id)],
    ]);
    if (ok != true) throw ApiException('NZBGet didn\'t accept that change.');
  }

  @override
  Future<void> pauseAll() => call('pausedownload');
  @override
  Future<void> resumeAll() => call('resumedownload');
  @override
  Future<void> pause(DownloadItem item) => _edit('GroupPause', item.id);
  @override
  Future<void> resume(DownloadItem item) => _edit('GroupResume', item.id);
  @override
  Future<void> remove(DownloadItem item, {bool deleteData = false}) =>
      _edit('GroupFinalDelete', item.id);
  @override
  Future<void> removeHistory(HistoryItem item) =>
      _edit('HistoryDelete', item.id);

  @override
  Future<void> addUrl(String url, {String? category}) async {
    // append(NZBFilename, Content, Category, Priority, AddToTop, AddPaused,
    //        DupeKey, DupeScore, DupeMode, PPParameters). Content may be a URL.
    final id = await call('append', [
      '',
      url,
      category ?? '',
      0,
      false,
      false,
      '',
      0,
      'SCORE',
      [],
    ]);
    if (id is int && id <= 0) {
      throw ApiException('NZBGet couldn\'t add that link.');
    }
  }
}

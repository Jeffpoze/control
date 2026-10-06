import '../util/format.dart';
import 'download_client.dart';
import 'service_client.dart';

/// qBittorrent, through its Web API (`/api/v2`). Logs in with a cookie and
/// logs in again when the session expires.
class QbittorrentClient extends DownloadClient {
  QbittorrentClient(super.server, {super.httpClient});

  @override
  bool get hasHistory => false;
  @override
  bool get canDeleteData => true;

  String? _cookie;

  /// qBittorrent 5 renamed pause/resume to stop/start.
  bool? _usesStopStart;

  @override
  Map<String, String> authHeaders() => {'Cookie': ?_cookie};

  Future<void> _login() async {
    final res = await request(
      'POST',
      '/api/v2/auth/login',
      form: {'username': server.username, 'password': server.password},
      headers: {
        'Referer': activeBase?.toString() ?? server.baseUris.first.toString(),
      },
      checkStatus: false,
    );
    if (res.statusCode == 403) {
      throw ApiException(
        'qBittorrent has blocked this device after too many failed logins. Try again later.',
      );
    }
    final setCookie = res.headers['set-cookie'];
    final sid = setCookie == null
        ? null
        : RegExp(r'(SID|QBT_SID_\d+)=([^;]+)').firstMatch(setCookie);
    if (sid != null) {
      _cookie = '${sid.group(1)}=${sid.group(2)}';
    } else if (res.body.trim() == 'Ok.') {
      // Auth bypassed for this network (localhost or whitelisted subnet).
      _cookie = null;
    } else {
      throw ApiException('qBittorrent rejected the username or password.');
    }
  }

  /// Sends a request, logging in first if needed and once more on a 403.
  Future<dynamic> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
    Map<String, String>? multipart,
    bool json = true,
  }) async {
    if (_cookie == null && server.username.isNotEmpty) await _login();
    var res = await request(
      method,
      path,
      query: query,
      form: form,
      multipart: multipart,
      checkStatus: false,
    );
    if (res.statusCode == 403) {
      await _login();
      res = await request(
        method,
        path,
        query: query,
        form: form,
        multipart: multipart,
        checkStatus: false,
      );
    }
    if (res.statusCode == 404) throw _NotFound();
    if (res.statusCode >= 400) {
      throw ApiException(
        'qBittorrent returned an error (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    return json ? ServiceClient.decode(res) : res.body;
  }

  @override
  Future<DownloadSnapshot> snapshot() async {
    final results = await Future.wait([
      _api(
        'GET',
        '/api/v2/torrents/info',
        query: {'sort': 'added_on', 'reverse': 'true'},
      ),
      _api('GET', '/api/v2/transfer/info'),
    ]);
    final transfer = (results[1] as Map).cast<String, dynamic>();
    return DownloadSnapshot(
      items: [
        for (final t in results[0] as List) parseTorrent((t as Map).cast()),
      ],
      downSpeed: asInt(transfer['dl_info_speed']),
      upSpeed: asInt(transfer['up_info_speed']),
    );
  }

  static DownloadItem parseTorrent(Map<String, dynamic> t) {
    final raw = (t['state'] ?? '').toString();
    final state = stateOf(raw);
    final size = asInt(t['size']);
    final progress = asDouble(t['progress']).clamp(0, 1).toDouble();
    final eta = asInt(t['eta']);
    return DownloadItem(
      id: t['hash'].toString(),
      name: (t['name'] ?? '').toString(),
      state: state,
      statusText: raw,
      progress: progress,
      sizeBytes: size,
      remainingBytes: asInt(t['amount_left']),
      downSpeed: asInt(t['dlspeed']),
      upSpeed: asInt(t['upspeed']),
      // 8640000 is qBittorrent's "infinity".
      eta: eta > 0 && eta < 8640000 && state == DownloadState.downloading
          ? Duration(seconds: eta)
          : null,
      category: (t['category'] as String?)?.isEmpty ?? true
          ? null
          : t['category'] as String,
      ratio: asDouble(t['ratio']),
    );
  }

  static DownloadState stateOf(String raw) => switch (raw) {
    'downloading' ||
    'forcedDL' ||
    'metaDL' ||
    'forcedMetaDL' ||
    'stalledDL' => DownloadState.downloading,
    'pausedDL' || 'stoppedDL' => DownloadState.paused,
    'pausedUP' || 'stoppedUP' => DownloadState.completed,
    'queuedDL' || 'queuedUP' => DownloadState.queued,
    'uploading' || 'stalledUP' || 'forcedUP' => DownloadState.seeding,
    'checkingDL' ||
    'checkingUP' ||
    'checkingResumeData' ||
    'allocating' => DownloadState.checking,
    'moving' => DownloadState.processing,
    'error' || 'missingFiles' => DownloadState.error,
    _ => DownloadState.queued,
  };

  Future<void> _toggle(bool stop, String hashes) async {
    final modern = stop ? 'stop' : 'start';
    final legacy = stop ? 'pause' : 'resume';
    if (_usesStopStart != false) {
      try {
        await _api(
          'POST',
          '/api/v2/torrents/$modern',
          form: {'hashes': hashes},
          json: false,
        );
        _usesStopStart = true;
        return;
      } on _NotFound {
        _usesStopStart = false;
      }
    }
    await _api(
      'POST',
      '/api/v2/torrents/$legacy',
      form: {'hashes': hashes},
      json: false,
    );
  }

  @override
  Future<void> pauseAll() => _toggle(true, 'all');
  @override
  Future<void> resumeAll() => _toggle(false, 'all');
  @override
  Future<void> pause(DownloadItem item) => _toggle(true, item.id);
  @override
  Future<void> resume(DownloadItem item) => _toggle(false, item.id);

  @override
  Future<void> remove(DownloadItem item, {bool deleteData = false}) => _api(
    'POST',
    '/api/v2/torrents/delete',
    form: {'hashes': item.id, 'deleteFiles': deleteData.toString()},
    json: false,
  );

  @override
  Future<void> addUrl(String url, {String? category}) async {
    final body = await _api(
      'POST',
      '/api/v2/torrents/add',
      multipart: {
        'urls': url,
        if (category != null && category.isNotEmpty) 'category': category,
      },
      json: false,
    );
    if (body is String && body.trim() == 'Fails.') {
      throw ApiException('qBittorrent couldn\'t add that link.');
    }
  }
}

class _NotFound implements Exception {}

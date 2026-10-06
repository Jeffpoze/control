import 'service_client.dart';

enum DownloadState {
  downloading,
  queued,
  paused,
  seeding,
  completed,
  checking,
  processing,
  error,
}

extension DownloadStateLabel on DownloadState {
  String get label => switch (this) {
    DownloadState.downloading => 'Downloading',
    DownloadState.queued => 'Queued',
    DownloadState.paused => 'Paused',
    DownloadState.seeding => 'Seeding',
    DownloadState.completed => 'Completed',
    DownloadState.checking => 'Checking',
    DownloadState.processing => 'Processing',
    DownloadState.error => 'Error',
  };

  bool get isPaused => this == DownloadState.paused;
}

/// One item in a download client's queue (an NZB or a torrent).
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.name,
    required this.state,
    this.statusText,
    this.progress = 0,
    this.sizeBytes = 0,
    this.remainingBytes = 0,
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.eta,
    this.category,
    this.ratio,
  });

  final String id;
  final String name;
  final DownloadState state;

  /// The client's own wording, when it says more than [state].
  final String? statusText;

  /// 0.0 to 1.0.
  final double progress;
  final int sizeBytes;
  final int remainingBytes;

  /// Bytes per second.
  final int downSpeed;
  final int upSpeed;
  final Duration? eta;
  final String? category;
  final double? ratio;
}

/// A finished (or failed) download, for usenet clients.
class HistoryItem {
  HistoryItem({
    required this.id,
    required this.name,
    required this.succeeded,
    this.statusText = '',
    this.sizeBytes = 0,
    this.completedAt,
    this.category,
    this.failMessage,
  });

  final String id;
  final String name;
  final bool succeeded;
  final String statusText;
  final int sizeBytes;
  final DateTime? completedAt;
  final String? category;
  final String? failMessage;
}

class DownloadSnapshot {
  DownloadSnapshot({
    required this.items,
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.paused = false,
    this.remainingBytes,
    this.freeSpaceBytes,
  });

  final List<DownloadItem> items;
  final int downSpeed;
  final int upSpeed;

  /// The whole client is paused (usenet clients).
  final bool paused;
  final int? remainingBytes;
  final int? freeSpaceBytes;

  int get activeCount =>
      items.where((i) => i.state == DownloadState.downloading).length;
}

/// What every download client can do, so one screen can drive them all.
abstract class DownloadClient extends ServiceClient {
  DownloadClient(super.server, {super.httpClient});

  /// Usenet clients keep a separate history; torrent clients keep finished
  /// torrents in the list.
  bool get hasHistory;

  /// Torrent clients can keep or delete downloaded data when removing.
  bool get canDeleteData;

  Future<DownloadSnapshot> snapshot();
  Future<List<HistoryItem>> history() async => const [];
  Future<void> pauseAll();
  Future<void> resumeAll();
  Future<void> pause(DownloadItem item);
  Future<void> resume(DownloadItem item);
  Future<void> remove(DownloadItem item, {bool deleteData = false});
  Future<void> removeHistory(HistoryItem item) async {}

  /// Adds an NZB link, torrent link or magnet.
  Future<void> addUrl(String url, {String? category});

  @override
  Future<void> test() => snapshot();
}

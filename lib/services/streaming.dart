/// Someone watching or listening right now, on Plex (through Tautulli),
/// Emby or Jellyfin.
class PlaySession {
  PlaySession({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.user = '',
    this.player = '',
    this.progress = 0,
    this.state = 'playing',
    this.transcoding = false,
    this.quality = '',
    this.thumbUrl,
  });

  /// What the server needs to stop this stream.
  final String id;
  final String title;
  final String subtitle;
  final String user;
  final String player;

  /// 0…1 through the item.
  final double progress;

  /// "playing", "paused" or "buffering".
  final String state;
  final bool transcoding;
  final String quality;
  final String? thumbUrl;
}

class Activity {
  Activity(this.sessions, {this.bandwidthKbps});
  final List<PlaySession> sessions;

  /// Total streaming bandwidth, when the server reports it.
  final int? bandwidthKbps;
}

/// A server that can say who's playing what, and stop a stream.
abstract interface class StreamingClient {
  Future<Activity> activity();
  Future<void> terminate(PlaySession session, {String message = ''});
}

import 'package:flutter/material.dart';

/// What a service is for. Drives where it shows up in the app.
enum ServiceGroup {
  downloader,
  media,
  library,
  indexer,
  requests,
  mediaServer,
  notifications,
}

/// How a service authenticates.
enum AuthStyle { apiKey, login }

/// Every service Control can talk to.
enum ServiceKind {
  sabnzbd(
    'SABnzbd',
    ServiceGroup.downloader,
    AuthStyle.apiKey,
    8080,
    Icons.cloud_download_outlined,
  ),
  nzbget(
    'NZBGet',
    ServiceGroup.downloader,
    AuthStyle.login,
    6789,
    Icons.cloud_download_outlined,
  ),
  qbittorrent(
    'qBittorrent',
    ServiceGroup.downloader,
    AuthStyle.login,
    8080,
    Icons.swap_vert_circle_outlined,
  ),
  transmission(
    'Transmission',
    ServiceGroup.downloader,
    AuthStyle.login,
    9091,
    Icons.swap_vert_circle_outlined,
  ),
  sonarr('Sonarr', ServiceGroup.media, AuthStyle.apiKey, 8989, Icons.tv),
  radarr(
    'Radarr',
    ServiceGroup.media,
    AuthStyle.apiKey,
    7878,
    Icons.movie_outlined,
  ),
  lidarr(
    'Lidarr',
    ServiceGroup.media,
    AuthStyle.apiKey,
    8686,
    Icons.library_music_outlined,
  ),
  prowlarr(
    'Prowlarr',
    ServiceGroup.indexer,
    AuthStyle.apiKey,
    9696,
    Icons.travel_explore,
  ),
  overseerr(
    'Overseerr / Jellyseerr',
    ServiceGroup.requests,
    AuthStyle.apiKey,
    5055,
    Icons.playlist_add_check,
  ),
  tautulli(
    'Tautulli',
    ServiceGroup.mediaServer,
    AuthStyle.apiKey,
    8181,
    Icons.insights_outlined,
  ),
  emby('Emby', ServiceGroup.mediaServer, AuthStyle.apiKey, 8096, Icons.live_tv),
  jellyfin(
    'Jellyfin',
    ServiceGroup.mediaServer,
    AuthStyle.apiKey,
    8096,
    Icons.smart_display_outlined,
  ),
  bazarr(
    'Bazarr',
    ServiceGroup.library,
    AuthStyle.apiKey,
    6767,
    Icons.subtitles_outlined,
  ),
  comicarr(
    'Comicarr',
    ServiceGroup.library,
    AuthStyle.login,
    8090,
    Icons.auto_stories_outlined,
  ),
  tracearr(
    'Tracearr',
    ServiceGroup.mediaServer,
    AuthStyle.apiKey,
    3000,
    Icons.query_stats,
  ),
  tmdb(
    'TMDB',
    ServiceGroup.requests,
    AuthStyle.apiKey,
    443,
    Icons.local_movies_outlined,
  ),
  ntfy(
    'ntfy',
    ServiceGroup.notifications,
    AuthStyle.apiKey,
    80,
    Icons.notifications_outlined,
  );

  const ServiceKind(
    this.label,
    this.group,
    this.auth,
    this.defaultPort,
    this.icon,
  );

  final String label;
  final ServiceGroup group;
  final AuthStyle auth;
  final int defaultPort;
  final IconData icon;

  /// Whether a username is required (NZBGet and Transmission allow blank).
  bool get usernameOptional =>
      this == ServiceKind.nzbget || this == ServiceKind.transmission;

  /// What Media calls this kind: TV, Movies, Music.
  String get mediaLabel => switch (this) {
    ServiceKind.sonarr => 'TV',
    ServiceKind.radarr => 'Movies',
    ServiceKind.lidarr => 'Music',
    _ => label,
  };

  /// Servers that can say who's watching what.
  static const streaming = {
    ServiceKind.tautulli,
    ServiceKind.tracearr,
    ServiceKind.emby,
    ServiceKind.jellyfin,
  };

  /// Apps that can send ntfy notifications, and that Control can set up.
  static const notifiers = {
    ServiceKind.sonarr,
    ServiceKind.radarr,
    ServiceKind.lidarr,
    ServiceKind.sabnzbd,
  };

  /// ntfy only needs a token when the server requires login.
  bool get apiKeyOptional => this == ServiceKind.ntfy;

  String get apiKeyLabel =>
      this == ServiceKind.ntfy ? 'Access token (optional)' : 'API key';

  /// Where users find their API key, shown under the field.
  String get apiKeyHint => switch (this) {
    ServiceKind.sabnzbd => 'Config → General → Security → API Key',
    ServiceKind.tautulli => 'Settings → Web Interface → API Key',
    ServiceKind.overseerr => 'Settings → General → API Key',
    ServiceKind.emby => 'Settings → Advanced → API Keys → New API Key',
    ServiceKind.jellyfin => 'Dashboard → API Keys → +',
    ServiceKind.tracearr =>
      'Settings → General → API key (starts with trr_pub_)',
    ServiceKind.ntfy => 'Only if your ntfy server requires login (tk_…)',
    ServiceKind.tmdb => 'Free at themoviedb.org → Settings → API. The API key or the Read Access Token both work.',
    _ => 'Settings → General → Security → API Key',
  };
}

/// One configured server. Secrets (API key, passwords) are kept in the
/// secure storage (Keychain on iOS) by [ServerStore], not in [toJson].
class ServerConfig {
  ServerConfig({
    required this.id,
    required this.kind,
    required this.name,
    this.localUrl = '',
    this.remoteUrl = '',
    this.apiKey = '',
    this.username = '',
    this.password = '',
    this.proxyUser = '',
    this.proxyPassword = '',
    this.customHeaders = '',
  });

  final String id;
  final ServiceKind kind;
  final String name;

  /// Address on the home network, tried first (for example http://192.168.1.10:8989).
  final String localUrl;

  /// Address from outside (reverse proxy or VPN), used when local isn't reachable.
  final String remoteUrl;

  final String apiKey;
  final String username;
  final String password;

  /// HTTP basic auth in front of the service (a reverse proxy, for example).
  final String proxyUser;
  final String proxyPassword;

  /// Extra headers sent with every request, one "Name: value" per line
  /// (Cloudflare Access service tokens, Authelia…). Kept in secure storage, as
  /// they're often credentials.
  final String customHeaders;

  Map<String, String> get headerMap => parseHeaderLines(customHeaders);

  /// "TV", or "TV · 4K" when the user named a second Sonarr "4K".
  String get mediaLabel => name == kind.label || name.isEmpty
      ? kind.mediaLabel
      : '${kind.mediaLabel} · $name';

  List<Uri> get baseUris => [
    localUrl,
    remoteUrl,
  ].map((u) => u.trim()).where((u) => u.isNotEmpty).map(normalizeUrl).toList();

  ServerConfig copyWith({
    String? name,
    String? localUrl,
    String? remoteUrl,
    String? apiKey,
    String? username,
    String? password,
    String? proxyUser,
    String? proxyPassword,
    String? customHeaders,
  }) => ServerConfig(
    id: id,
    kind: kind,
    name: name ?? this.name,
    localUrl: localUrl ?? this.localUrl,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    apiKey: apiKey ?? this.apiKey,
    username: username ?? this.username,
    password: password ?? this.password,
    proxyUser: proxyUser ?? this.proxyUser,
    proxyPassword: proxyPassword ?? this.proxyPassword,
    customHeaders: customHeaders ?? this.customHeaders,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'localUrl': localUrl,
    'remoteUrl': remoteUrl,
    'username': username,
    'proxyUser': proxyUser,
  };

  Map<String, String> secretsJson() => {
    'apiKey': apiKey,
    'password': password,
    'proxyPassword': proxyPassword,
    'customHeaders': customHeaders,
  };

  static ServerConfig? fromJson(
    Map<String, dynamic> json,
    Map<String, dynamic> secrets,
  ) {
    final kind = ServiceKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) return null;
    return ServerConfig(
      id: json['id'] as String,
      kind: kind,
      name: (json['name'] as String?) ?? kind.label,
      localUrl: (json['localUrl'] as String?) ?? '',
      remoteUrl: (json['remoteUrl'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      proxyUser: (json['proxyUser'] as String?) ?? '',
      apiKey: (secrets['apiKey'] as String?) ?? '',
      password: (secrets['password'] as String?) ?? '',
      proxyPassword: (secrets['proxyPassword'] as String?) ?? '',
      customHeaders: (secrets['customHeaders'] as String?) ?? '',
    );
  }
}

/// Accepts "192.168.1.10:8989", "nas.local:8080/sonarr/" or a full URL and
/// returns a URL with a scheme and no trailing slash.
Uri normalizeUrl(String input) {
  var s = input.trim();
  if (!s.contains('://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return Uri.parse(s);
}

/// "Name: value" lines to a header map. Blank lines, lines without a colon
/// and names with spaces are skipped.
Map<String, String> parseHeaderLines(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final name = line.substring(0, i).trim();
    if (name.isEmpty || name.contains(' ')) continue;
    out[name] = line.substring(i + 1).trim();
  }
  return out;
}

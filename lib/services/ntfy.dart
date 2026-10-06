import 'dart:math';

import '../models/server.dart';
import 'service_client.dart';

/// Which events to send to the phone.
class NotifyEvents {
  const NotifyEvents({
    this.imports = true,
    this.grabs = false,
    this.problems = true,
    this.sabComplete = false,
  });

  /// Sonarr, Radarr and Lidarr imported or upgraded something.
  final bool imports;

  /// Sonarr, Radarr and Lidarr sent something to a download client.
  final bool grabs;

  /// Failed downloads, failed imports, health issues, a full disk.
  final bool problems;

  /// SABnzbd finished any download (useful without an *arr).
  final bool sabComplete;

  Map<String, dynamic> toJson() => {
    'imports': imports,
    'grabs': grabs,
    'problems': problems,
    'sabComplete': sabComplete,
  };

  static NotifyEvents fromJson(Map<String, dynamic> j) => NotifyEvents(
    imports: j['imports'] != false,
    grabs: j['grabs'] == true,
    problems: j['problems'] != false,
    sabComplete: j['sabComplete'] == true,
  );
}

/// Where notifications go: an ntfy server (ntfy.sh by default) and a topic.
/// The topic is the only thing protecting a public server's messages, so it
/// is long and random, and kept in secure storage.
class NotifySettings {
  NotifySettings({
    required this.topic,
    this.serverId,
    this.events = const NotifyEvents(),
  });

  /// A configured ntfy server, or null for the public ntfy.sh.
  final String? serverId;
  final String topic;
  final NotifyEvents events;

  NotifySettings copyWith({
    String? topic,
    String? serverId,
    bool publicServer = false,
    NotifyEvents? events,
  }) => NotifySettings(
    topic: topic ?? this.topic,
    serverId: publicServer ? null : serverId ?? this.serverId,
    events: events ?? this.events,
  );

  Map<String, dynamic> toJson() => {
    'topic': topic,
    'serverId': serverId,
    'events': events.toJson(),
  };

  static NotifySettings fromJson(Map<String, dynamic> j) => NotifySettings(
    topic: (j['topic'] ?? '').toString(),
    serverId: j['serverId'] as String?,
    events: NotifyEvents.fromJson(
      (j['events'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );
}

/// What another app needs to publish to ntfy, and what the phone needs to
/// subscribe.
class NtfyTarget {
  NtfyTarget({
    required this.publishUrl,
    required this.subscribeUrl,
    required this.topic,
    this.token = '',
  });

  /// Used by Sonarr, Radarr and SABnzbd, which usually sit next to a
  /// self-hosted ntfy, so the home address comes first.
  final Uri publishUrl;

  /// Used by the phone, which may be away, so the away address comes first.
  final Uri subscribeUrl;
  final String topic;
  final String token;

  static NtfyTarget of(ServerConfig ntfy, String topic) {
    final local = ntfy.localUrl.trim();
    final remote = ntfy.remoteUrl.trim();
    return NtfyTarget(
      publishUrl: normalizeUrl(local.isNotEmpty ? local : remote),
      subscribeUrl: normalizeUrl(remote.isNotEmpty ? remote : local),
      topic: topic,
      token: ntfy.apiKey.trim(),
    );
  }

  /// The topic page, which also works in a browser.
  Uri get webUrl => joinUri(subscribeUrl, '/$topic');

  /// Opens the ntfy app's subscribe screen (Android supports these links).
  Uri get appUrl {
    final secure = subscribeUrl.scheme == 'https';
    final host = subscribeUrl.hasPort
        ? '${subscribeUrl.host}:${subscribeUrl.port}'
        : subscribeUrl.host;
    return Uri.parse(
      'ntfy://$host${subscribeUrl.path}/$topic${secure ? '' : '?secure=false'}',
    );
  }

  /// The same target as an Apprise URL, which is how SABnzbd sends to ntfy.
  String get appriseUrl {
    final scheme = publishUrl.scheme == 'https' ? 'ntfys' : 'ntfy';
    final auth = token.isEmpty ? '' : '$token@';
    final host = publishUrl.hasPort
        ? '${publishUrl.host}:${publishUrl.port}'
        : publishUrl.host;
    return '$scheme://$auth$host${publishUrl.path}/$topic';
  }
}

/// The public ntfy.sh server, used when no ntfy server is configured.
final publicNtfy = ServerConfig(
  id: 'ntfy.sh',
  kind: ServiceKind.ntfy,
  name: 'ntfy.sh',
  remoteUrl: 'https://ntfy.sh',
);

/// A topic nobody will guess: "control_" and 20 random letters and digits.
String randomTopic([Random? random]) {
  const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = random ?? Random.secure();
  return 'control_${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
}

class NtfyClient extends ServiceClient {
  NtfyClient(super.server, {super.httpClient});

  @override
  Map<String, String> authHeaders() => server.apiKey.trim().isEmpty
      ? const {}
      : {'Authorization': 'Bearer ${server.apiKey.trim()}'};

  @override
  Future<void> test() async {
    final json = await getJson('/v1/health');
    if (json is! Map || json['healthy'] != true) {
      throw ApiException('That address answered, but it isn\'t ntfy.');
    }
  }

  /// Sends a message straight to the topic, to check the phone receives it.
  Future<void> publish(String topic, String message, {String? title}) =>
      request('POST', '/$topic', headers: {'Title': ?title}, body: message);
}

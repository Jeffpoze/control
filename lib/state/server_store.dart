import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/clients.dart';
import '../services/ntfy.dart';

/// Where secrets live. The app uses the iOS Keychain; tests use memory.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The configured servers, and one live client per server.
class ServerStore extends ChangeNotifier {
  ServerStore({SecretStore? secrets})
    : _secrets = secrets ?? KeychainSecretStore();

  static const _prefsKey = 'servers.v1';
  static const _notifyKey = 'notify.v1';

  /// The server list is also kept in secure storage. On iPhone the Keychain
  /// survives deleting and reinstalling the app, so the setup comes back.
  static const _listKey = 'servers.list.v1';

  final SecretStore _secrets;
  final Map<String, ServiceClient> _clients = {};
  List<ServerConfig> _servers = [];
  bool loaded = false;

  /// Where notifications go; null until set up. Kept in secure storage, as
  /// anyone with the topic can read the notifications.
  NotifySettings? notify;

  List<ServerConfig> get servers => List.unmodifiable(_servers);

  List<ServerConfig> ofGroup(ServiceGroup group) =>
      _servers.where((s) => s.kind.group == group).toList();

  List<ServerConfig> ofKinds(Set<ServiceKind> kinds) =>
      _servers.where((s) => kinds.contains(s.kind)).toList();

  ServerConfig? byId(String id) =>
      _servers.where((s) => s.id == id).firstOrNull;

  /// The client for [server], created on first use and kept so sessions
  /// (qBittorrent cookie, Transmission session id, local/remote choice) last.
  T client<T extends ServiceClient>(ServerConfig server) =>
      _clients.putIfAbsent(server.id, () => createClient(server)) as T;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kept = await _secrets.read(_listKey);
    final raw = kept ?? prefs.getString(_prefsKey);
    final list = <ServerConfig>[];
    if (raw != null) {
      for (final item in jsonDecode(raw) as List) {
        final json = (item as Map).cast<String, dynamic>();
        final secretRaw = await _secrets.read('server.${json['id']}');
        final secrets = secretRaw == null
            ? <String, dynamic>{}
            : (jsonDecode(secretRaw) as Map).cast<String, dynamic>();
        final server = ServerConfig.fromJson(json, secrets);
        if (server != null) list.add(server);
      }
    }
    _servers = list;
    // First run with this version: copy the list into secure storage too.
    if (kept == null && list.isNotEmpty) await _persist();
    final notifyRaw = await _secrets.read(_notifyKey);
    if (notifyRaw != null) {
      notify = NotifySettings.fromJson(
        (jsonDecode(notifyRaw) as Map).cast<String, dynamic>(),
      );
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> saveNotify(NotifySettings settings) async {
    notify = settings;
    await _secrets.write(_notifyKey, jsonEncode(settings.toJson()));
    notifyListeners();
  }

  /// The ntfy server notifications go through.
  ServerConfig ntfyServer() =>
      (notify?.serverId == null ? null : byId(notify!.serverId!)) ?? publicNtfy;

  Future<void> save(ServerConfig server) async {
    final i = _servers.indexWhere((s) => s.id == server.id);
    if (i >= 0) {
      _servers[i] = server;
    } else {
      _servers.add(server);
    }
    _clients.remove(server.id)?.close();
    await _secrets.write(
      'server.${server.id}',
      jsonEncode(server.secretsJson()),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _servers.removeWhere((s) => s.id == id);
    _clients.remove(id)?.close();
    await _secrets.delete('server.$id');
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final list = jsonEncode(_servers.map((s) => s.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, list);
    await _secrets.write(_listKey, list);
  }

  /// Every server with its keys and passwords, and the notification
  /// settings, as text to keep somewhere safe or move to another phone.
  String exportBackup() => const JsonEncoder.withIndent('  ').convert({
    'app': 'Control',
    'version': 1,
    'servers': [
      for (final s in _servers) {...s.toJson(), 'secrets': s.secretsJson()},
    ],
    if (notify != null) 'notify': notify!.toJson(),
  });

  /// Reads a backup made by [exportBackup]. Throws [FormatException] with a
  /// message fit to show when the text isn't one.
  static (List<ServerConfig>, NotifySettings?) parseBackup(String text) {
    Object? json;
    try {
      json = jsonDecode(text.trim());
    } on FormatException {
      throw const FormatException('That isn\'t a Control backup.');
    }
    if (json is! Map || json['app'] != 'Control' || json['servers'] is! List) {
      throw const FormatException('That isn\'t a Control backup.');
    }
    final servers = <ServerConfig>[
      for (final item in json['servers'] as List)
        if (item is Map)
          ?ServerConfig.fromJson(
            item.cast<String, dynamic>(),
            ((item['secrets'] as Map?) ?? const {}).cast<String, dynamic>(),
          ),
    ];
    final notify = json['notify'] is Map
        ? NotifySettings.fromJson((json['notify'] as Map).cast())
        : null;
    return (servers, notify);
  }

  /// Adds the servers from a backup; ones with the same id are replaced.
  /// Returns how many were restored.
  Future<int> importBackup(String text) async {
    final (servers, notifySettings) = parseBackup(text);
    for (final s in servers) {
      await save(s);
    }
    if (notifySettings != null) await saveNotify(notifySettings);
    return servers.length;
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

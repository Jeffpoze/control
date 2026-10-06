import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/clients.dart';

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

  final SecretStore _secrets;
  final Map<String, ServiceClient> _clients = {};
  List<ServerConfig> _servers = [];
  bool loaded = false;

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
    final raw = prefs.getString(_prefsKey);
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
    loaded = true;
    notifyListeners();
  }

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_servers.map((s) => s.toJson()).toList()),
    );
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

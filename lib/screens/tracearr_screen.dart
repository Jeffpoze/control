import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/service_client.dart';
import '../services/tracearr.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'activity_screen.dart';
import 'servers_screen.dart';

/// Tracearr: today's numbers, rule alerts and play history across Plex,
/// Jellyfin and Emby. Its live streams also show in Now playing.
class TracearrScreen extends StatefulWidget {
  const TracearrScreen({super.key});

  @override
  State<TracearrScreen> createState() => _TracearrScreenState();
}

class _TracearrScreenState extends State<TracearrScreen> {
  String? _serverId;
  TracearrToday? _today;
  List<TracearrPlay>? _history;
  List<TracearrAlert> _alerts = const [];
  Object? _error;

  ServerConfig? _server(ServerStore store) {
    final servers = store.ofKinds({ServiceKind.tracearr});
    return servers.where((s) => s.id == _serverId).firstOrNull ??
        servers.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<ServerStore>();
    final server = _server(store);
    if (server == null) return;
    final client = store.client<TracearrClient>(server);
    setState(() => _error = null);
    try {
      final today = await client.today();
      final history = await client.history();
      List<TracearrAlert> alerts = const [];
      try {
        alerts = await client.alerts();
      } on ApiException {
        // Older Tracearr versions don't expose alerts; the rest still works.
      }
      if (!mounted) return;
      setState(() {
        _today = today;
        _history = history;
        _alerts = alerts;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final server = _server(store);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stats and history')),
        body: NoServersView(
          what: 'Tracearr',
          onAdd: () => addServer(context, group: ServiceGroup.other),
        ),
      );
    }
    final theme = Theme.of(context);
    final today = _today;
    final history = _history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats and history'),
        actions: [
          IconButton(
            tooltip: 'Now playing',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          ServerPicker(
            servers: store.ofKinds({ServiceKind.tracearr}),
            selectedId: server.id,
            onSelected: (s) {
              setState(() {
                _serverId = s.id;
                _today = null;
                _history = null;
              });
              _load();
            },
          ),
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : history == null || today == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Tile('Watching now', '${today.activeStreams}'),
                              _Tile('Plays today', '${today.plays}'),
                              _Tile(
                                'Watch time today',
                                '${today.watchHours.toStringAsFixed(1)} h',
                              ),
                              _Tile('Viewers today', '${today.activeUsers}'),
                              _Tile(
                                'Alerts, last 24 h',
                                '${today.alerts}',
                                warn: today.alerts > 0,
                              ),
                            ],
                          ),
                        ),
                        if (_alerts.isNotEmpty) ...[
                          const SectionHeader('Alerts'),
                          for (final a in _alerts.take(10))
                            ListTile(
                              leading: Icon(
                                Icons.shield_outlined,
                                color: switch (a.severity) {
                                  'high' => theme.colorScheme.error,
                                  'warning' => Colors.orange,
                                  _ => theme.colorScheme.outline,
                                },
                              ),
                              title: Text(a.rule),
                              subtitle: Text(
                                [
                                  a.user,
                                  a.server,
                                  if (a.createdAt != null)
                                    formatAgo(a.createdAt!),
                                ].where((x) => x.isNotEmpty).join(' · '),
                              ),
                            ),
                        ],
                        const SectionHeader('Recent plays'),
                        if (history.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Nothing played yet.'),
                          ),
                        for (final p in history) _PlayTile(play: p),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: warn ? Colors.orange : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayTile extends StatelessWidget {
  const _PlayTile({required this.play});
  final TracearrPlay play;

  @override
  Widget build(BuildContext context) {
    final p = play;
    final minutes = (p.watchedMs / 60000).round();
    return ListTile(
      leading: Poster(
        url: p.posterUrl,
        width: 40,
        height: 60,
        icon: Icons.play_circle_outline,
      ),
      title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (p.subtitle.isNotEmpty) p.subtitle,
          [
            p.user,
            if (p.player.isNotEmpty) p.player,
            if (p.startedAt != null) formatAgo(p.startedAt!),
            if (minutes > 0) '$minutes min',
            if (p.transcode) 'Transcode',
          ].join(' · '),
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: p.subtitle.isNotEmpty,
      trailing: p.watched
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : null,
    );
  }
}

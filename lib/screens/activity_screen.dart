import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/clients.dart';
import '../services/streaming.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Who's watching what on Plex (through Tautulli), Emby and Jellyfin.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final Map<String, Activity> _activity = {};
  final Map<String, Object> _errors = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<ServerStore>();
    for (final s in store.ofKinds(ServiceKind.streaming)) {
      try {
        final a = await streamingClient(store, s).activity();
        if (mounted) setState(() => _activity[s.id] = a);
        _errors.remove(s.id);
      } catch (e) {
        if (mounted) setState(() => _errors[s.id] = e);
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _stop(StreamingClient client, PlaySession s) async {
    if (!await confirm(
      context,
      title: 'Stop ${s.user}\'s stream?',
      body: s.title,
      action: 'Stop stream',
    )) {
      return;
    }
    if (!mounted) return;
    if (await runAction(
      context,
      () => client.terminate(s),
      done: 'Stream stopped',
    )) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final servers = store.ofKinds(ServiceKind.streaming);
    return Scaffold(
      appBar: AppBar(title: const Text('Now playing')),
      body: servers.isEmpty
          ? NoServersView(
              what: 'Tautulli, Emby or Jellyfin',
              onAdd: () => addServer(context, group: ServiceGroup.mediaServer),
            )
          : !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  for (final server in servers) ...[
                    SectionHeader(
                      server.name,
                      trailing: _activity[server.id]?.bandwidthKbps == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${(_activity[server.id]!.bandwidthKbps! / 1000).toStringAsFixed(1)} Mbps',
                              ),
                            ),
                    ),
                    if (_errors[server.id] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          errorText(_errors[server.id]!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    else if (_activity[server.id]?.sessions.isEmpty ?? true)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Nobody is watching right now.'),
                      )
                    else
                      for (final s in _activity[server.id]!.sessions)
                        PlaySessionTile(
                          session: s,
                          onLongPress: () =>
                              _stop(streamingClient(store, server), s),
                        ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// The client for a Tautulli, Emby or Jellyfin server.
StreamingClient streamingClient(ServerStore store, ServerConfig server) =>
    store.client<ServiceClient>(server) as StreamingClient;

class PlaySessionTile extends StatelessWidget {
  const PlaySessionTile({super.key, required this.session, this.onLongPress});
  final PlaySession session;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    return ListTile(
      onLongPress: onLongPress,
      leading: Poster(
        url: s.thumbUrl,
        width: 40,
        height: 60,
        icon: Icons.play_circle_outline,
      ),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.subtitle.isNotEmpty)
            Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            [
              s.user,
              s.player,
              if (s.transcoding) 'Transcoding' else 'Direct',
              s.quality,
            ].where((x) => x.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: s.progress),
        ],
      ),
      trailing: Icon(s.state == 'paused' ? Icons.pause : Icons.play_arrow),
    );
  }
}

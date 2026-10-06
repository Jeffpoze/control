import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../services/download_client.dart';
import '../services/overseerr.dart';
import '../services/streaming.dart';
import '../state/nav_state.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/discover.dart';
import 'activity_screen.dart';
import 'arr_queue_screen.dart';
import 'calendar_screen.dart';
import 'downloads_screen.dart';
import 'requests_screen.dart';
import 'servers_screen.dart';

/// At-a-glance view: what's trending, what's downloading, each download
/// client, Plex activity, pending requests, what's coming up and what's
/// popular.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, DownloadSnapshot> _snapshots = {};
  final Map<String, Object> _errors = {};
  final Map<String, Activity> _activity = {};
  int? _pendingRequests;
  List<CalendarEntry>? _upcoming;
  final Map<DiscoverFeed, List<DiscoverResult>> _feeds = {};
  List<ActiveDownload> _active = const [];
  Timer? _timer;
  int _serverCount = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && context.read<NavState>().tab == NavState.home) {
        _loadDownloads();
        _loadActive();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() => Future.wait([
    _loadDownloads(),
    _loadActivity(),
    _loadRequests(),
    _loadUpcoming(),
    _loadDiscover(),
    _loadActive(),
  ]);

  OverseerrClient? _overseerr(ServerStore store) {
    final s = store.ofKinds({ServiceKind.overseerr}).firstOrNull;
    return s == null ? null : store.client<OverseerrClient>(s);
  }

  Future<void> _loadDiscover() async {
    final client = _overseerr(context.read<ServerStore>());
    if (client == null) return;
    await Future.wait(
      DiscoverFeed.values.map((feed) async {
        try {
          final items = await client.discover(feed);
          if (mounted) setState(() => _feeds[feed] = items);
        } catch (_) {
          // Discover is a nice-to-have; the requests card shows real errors.
        }
      }),
    );
  }

  Future<void> _loadActive() async {
    final store = context.read<ServerStore>();
    final arrs = store.ofGroup(ServiceGroup.media);
    if (arrs.isEmpty) return;
    final lists = await Future.wait(
      arrs.map((s) async {
        try {
          return await store.client<ArrClient>(s).activeDownloads();
        } catch (_) {
          return const <ActiveDownload>[];
        }
      }),
    );
    final all = lists.expand((l) => l).toList()
      ..sort((a, b) {
        if (a.isDownloading != b.isDownloading) {
          return a.isDownloading ? -1 : 1;
        }
        return b.progress.compareTo(a.progress);
      });
    if (mounted) setState(() => _active = all);
  }

  Future<void> _openDiscover(DiscoverResult r) async {
    final client = _overseerr(context.read<ServerStore>());
    if (client == null) return;
    final requested = await showDiscoverSheet(context, client, r);
    if (requested && mounted) {
      _loadDiscover();
      _loadRequests();
    }
  }

  void _openQueue(ActiveDownload item) {
    final store = context.read<ServerStore>();
    final server = store.byId(item.serverId);
    if (server == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArrQueueScreen(client: store.client<ArrClient>(server)),
      ),
    );
  }

  Future<void> _loadDownloads() async {
    final store = context.read<ServerStore>();
    await Future.wait(
      store.ofGroup(ServiceGroup.downloader).map((s) async {
        try {
          final snap = await store.client<DownloadClient>(s).snapshot();
          if (!mounted) return;
          setState(() {
            _snapshots[s.id] = snap;
            _errors.remove(s.id);
          });
        } catch (e) {
          if (mounted) setState(() => _errors[s.id] = e);
        }
      }),
    );
  }

  Future<void> _loadActivity() async {
    final store = context.read<ServerStore>();
    for (final s in store.ofKinds(ServiceKind.streaming)) {
      try {
        final a = await streamingClient(store, s).activity();
        if (mounted) setState(() => _activity[s.id] = a);
      } catch (e) {
        if (mounted) setState(() => _errors[s.id] = e);
      }
    }
  }

  Future<void> _loadRequests() async {
    final store = context.read<ServerStore>();
    var pending = 0;
    final servers = store.ofKinds({ServiceKind.overseerr});
    if (servers.isEmpty) return;
    for (final s in servers) {
      try {
        pending +=
            (await store.client<OverseerrClient>(s).requests(filter: 'pending'))
                .length;
      } catch (_) {}
    }
    if (mounted) setState(() => _pendingRequests = pending);
  }

  Future<void> _loadUpcoming() async {
    final store = context.read<ServerStore>();
    if (store.ofGroup(ServiceGroup.media).isEmpty) return;
    final now = DateTime.now();
    final (entries, _) = await loadCalendar(
      store,
      now,
      now.add(const Duration(days: 7)),
    );
    if (mounted) setState(() => _upcoming = entries);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    if (store.servers.length != _serverCount) {
      _serverCount = store.servers.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAll();
      });
    }
    final theme = Theme.of(context);
    final downloaders = store.ofGroup(ServiceGroup.downloader);
    final sessions = _activity.values.expand((a) => a.sessions).toList();
    final trending = _feeds[DiscoverFeed.trending] ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Control')),
      body: store.servers.isEmpty
          ? _Welcome(onAdd: () => addServer(context))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (trending.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TrendingBanner(
                      items: trending.take(10).toList(),
                      onTap: _openDiscover,
                    ),
                  ],
                  if (_active.isNotEmpty) ...[
                    SectionHeader('Now downloading · ${_active.length}'),
                    NowDownloadingStrip(items: _active, onTap: _openQueue),
                  ],
                  if (downloaders.isNotEmpty) ...[
                    const SectionHeader('Downloads'),
                    for (final s in downloaders)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _DownloaderCard(
                          server: s,
                          snapshot: _snapshots[s.id],
                          error: _errors[s.id],
                          onTap: () =>
                              context.read<NavState>().openDownloader(s.id),
                        ),
                      ),
                  ],
                  if (_pendingRequests != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Card(
                        child: ListTile(
                          leading: Icon(ServiceKind.overseerr.icon),
                          title: Text(
                            _pendingRequests == 0
                                ? 'No requests waiting'
                                : '$_pendingRequests request${_pendingRequests == 1 ? '' : 's'} waiting for approval',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RequestsScreen(),
                              ),
                            );
                            _loadRequests();
                          },
                        ),
                      ),
                    ),
                  if (store.ofKinds(ServiceKind.streaming).isNotEmpty) ...[
                    SectionHeader(
                      sessions.isEmpty
                          ? 'Nobody watching'
                          : 'Watching now · ${sessions.length}',
                      trailing: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActivityScreen(),
                          ),
                        ),
                        child: const Text('Details'),
                      ),
                    ),
                    for (final s in sessions.take(3))
                      PlaySessionTile(session: s),
                  ],
                  if (_upcoming != null) ...[
                    SectionHeader(
                      'Coming up this week',
                      trailing: TextButton(
                        onPressed: () =>
                            context.read<NavState>().go(NavState.calendar),
                        child: const Text('Calendar'),
                      ),
                    ),
                    if (_upcoming!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Nothing scheduled.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final e in _upcoming!.take(6)) CalendarTile(entry: e),
                  ],
                  for (final feed in DiscoverFeed.values.skip(1))
                    if ((_feeds[feed] ?? const []).isNotEmpty) ...[
                      SectionHeader(feed.label),
                      PosterRow(items: _feeds[feed]!, onTap: _openDiscover),
                    ],
                ],
              ),
            ),
    );
  }
}

class _DownloaderCard extends StatelessWidget {
  const _DownloaderCard({
    required this.server,
    required this.snapshot,
    required this.error,
    required this.onTap,
  });

  final ServerConfig server;
  final DownloadSnapshot? snapshot;
  final Object? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;
    final active =
        snap?.items
            .where((i) => i.state == DownloadState.downloading)
            .toList() ??
        [];
    final String status;
    if (error != null && snap == null) {
      status = errorText(error!);
    } else if (snap == null) {
      status = 'Connecting…';
    } else if (snap.paused) {
      status = 'Paused · ${snap.items.length} in queue';
    } else if (active.isEmpty) {
      status = snap.items.isEmpty
          ? 'Idle'
          : '${snap.items.length} items, none downloading';
    } else {
      status = '${active.length} downloading · ${snap.items.length} total';
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(server.kind.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      server.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (snap != null)
                    Text(
                      '↓ ${formatSpeed(snap.downSpeed)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error != null && snap == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (active.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  active.first.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: active.first.progress,
                  color: stateColor(context, active.first.state),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.tune,
    title: 'Welcome to Control',
    body:
        'Manage your download clients, Sonarr, Radarr, Lidarr, Bazarr, '
        'Prowlarr, Overseerr, Comicarr, Tautulli, Tracearr, Emby and Jellyfin '
        'from one place. '
        'Start by adding a server.',
    action: FilledButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('Add a server'),
    ),
  );
}

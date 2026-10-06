import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/download_client.dart';
import '../state/nav_state.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.active});

  /// Only poll while this tab is on screen.
  final bool active;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _interval = Duration(seconds: 3);

  Timer? _timer;
  String? _loadedFor;
  DownloadSnapshot? _snapshot;
  List<HistoryItem>? _history;
  Object? _error;
  bool _showHistory = false;
  bool _busy = false;

  ServerConfig? _current(BuildContext context) {
    final store = context.read<ServerStore>();
    final servers = store.ofGroup(ServiceGroup.downloader);
    if (servers.isEmpty) return null;
    final id = context.read<NavState>().downloaderId;
    return servers.where((s) => s.id == id).firstOrNull ?? servers.first;
  }

  DownloadClient? _client(BuildContext context) {
    final s = _current(context);
    return s == null
        ? null
        : context.read<ServerStore>().client<DownloadClient>(s);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPolling();
  }

  @override
  void didUpdateWidget(DownloadsScreen old) {
    super.didUpdateWidget(old);
    _syncPolling();
  }

  void _syncPolling() {
    if (widget.active && _timer == null) {
      _refresh();
      _timer = Timer.periodic(_interval, (_) => _refresh(quiet: true));
    } else if (!widget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_busy && quiet) return;
    final server = _current(context);
    final client = _client(context);
    if (server == null || client == null) return;
    if (_loadedFor != server.id) {
      _snapshot = null;
      _history = null;
      _error = null;
      _loadedFor = server.id;
      if (!client.hasHistory) _showHistory = false;
    }
    _busy = true;
    try {
      if (_showHistory && client.hasHistory) {
        final h = await client.history();
        if (mounted && _loadedFor == server.id) setState(() => _history = h);
      }
      final snap = await client.snapshot();
      if (mounted && _loadedFor == server.id) {
        setState(() {
          _snapshot = snap;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _loadedFor == server.id) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _act(Future<void> Function() action, {String? done}) async {
    if (await runAction(context, action, done: done)) await _refresh();
  }

  Future<void> _addLink(DownloadClient client) async {
    final url = await promptText(
      context,
      title: 'Add to ${client.server.name}',
      hint: client.canDeleteData ? 'Magnet or .torrent link' : 'NZB link',
    );
    if (url == null || url.isEmpty || !mounted) return;
    await _act(() => client.addUrl(url), done: 'Sent to ${client.server.name}');
  }

  void _itemActions(DownloadClient client, DownloadItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.state.isPaused || item.state == DownloadState.completed)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Resume'),
                onTap: () {
                  Navigator.pop(sheet);
                  _act(() => client.resume(item));
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.pause),
                title: const Text('Pause'),
                onTap: () {
                  Navigator.pop(sheet);
                  _act(() => client.pause(item));
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(
                client.canDeleteData ? 'Remove, keep files' : 'Delete',
              ),
              onTap: () async {
                Navigator.pop(sheet);
                if (await confirm(
                  context,
                  title: 'Remove this download?',
                  body: item.name,
                )) {
                  _act(() => client.remove(item), done: 'Removed');
                }
              },
            ),
            if (client.canDeleteData)
              ListTile(
                leading: Icon(
                  Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Remove and delete files'),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (await confirm(
                    context,
                    title: 'Delete the downloaded files too?',
                    body: item.name,
                  )) {
                    _act(
                      () => client.remove(item, deleteData: true),
                      done: 'Deleted',
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    context.watch<NavState>();
    final servers = store.ofGroup(ServiceGroup.downloader);
    final server = _current(context);
    final client = _client(context);

    if (server != null && _loadedFor != null && _loadedFor != server.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(server?.name ?? 'Downloads'),
        actions: [
          if (client != null) ...[
            IconButton(
              tooltip: 'Add link',
              icon: const Icon(Icons.add_link),
              onPressed: () => _addLink(client),
            ),
            if (_snapshot != null && !client.canDeleteData)
              IconButton(
                tooltip: _snapshot!.paused ? 'Resume all' : 'Pause all',
                icon: Icon(_snapshot!.paused ? Icons.play_arrow : Icons.pause),
                onPressed: () => _act(
                  _snapshot!.paused ? client.resumeAll : client.pauseAll,
                ),
              )
            else if (_snapshot != null)
              PopupMenuButton<String>(
                onSelected: (v) =>
                    _act(v == 'pause' ? client.pauseAll : client.resumeAll),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pause', child: Text('Pause all')),
                  PopupMenuItem(value: 'resume', child: Text('Resume all')),
                ],
              ),
          ],
        ],
      ),
      body: server == null || client == null
          ? NoServersView(
              what: 'download clients',
              onAdd: () => addServer(context, group: ServiceGroup.downloader),
            )
          : Column(
              children: [
                ServerPicker(
                  servers: servers,
                  selectedId: server.id,
                  onSelected: (s) =>
                      context.read<NavState>().openDownloader(s.id),
                ),
                if (_snapshot != null) _StatsBar(snapshot: _snapshot!),
                if (client.hasHistory)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Queue')),
                        ButtonSegment(value: true, label: Text('History')),
                      ],
                      selected: {_showHistory},
                      onSelectionChanged: (v) {
                        setState(() => _showHistory = v.first);
                        _refresh();
                      },
                    ),
                  ),
                Expanded(child: _body(client)),
              ],
            ),
    );
  }

  Widget _body(DownloadClient client) {
    if (_error != null && _snapshot == null) {
      return ErrorView(error: _error!, onRetry: _refresh);
    }
    if (_snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_showHistory) return _historyList(client);
    final items = _snapshot!.items;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                MessageView(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing downloading',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + (_error != null ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) {
                if (_error != null && i == 0) {
                  return MaterialBanner(
                    content: Text(errorText(_error!)),
                    actions: [
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final item = items[i - (_error != null ? 1 : 0)];
                return DownloadTile(
                  item: item,
                  onTap: () => _itemActions(client, item),
                );
              },
            ),
    );
  }

  Widget _historyList(DownloadClient client) {
    final history = _history;
    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: history.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                MessageView(icon: Icons.history, title: 'No history yet'),
              ],
            )
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) {
                final h = history[i];
                final theme = Theme.of(context);
                return ListTile(
                  leading: Icon(
                    h.succeeded
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: h.succeeded ? Colors.green : theme.colorScheme.error,
                  ),
                  title: Text(
                    h.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      formatBytes(h.sizeBytes),
                      ?h.category,
                      if (h.completedAt != null) formatAgo(h.completedAt!),
                      if (!h.succeeded) h.failMessage ?? h.statusText,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onLongPress: () async {
                    if (await confirm(
                      context,
                      title: 'Remove from history?',
                      body: h.name,
                    )) {
                      _act(() => client.removeHistory(h));
                    }
                  },
                );
              },
            ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.snapshot});
  final DownloadSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.labelLarge),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [
          stat(Icons.south, formatSpeed(snapshot.downSpeed)),
          if (snapshot.upSpeed > 0)
            stat(Icons.north, formatSpeed(snapshot.upSpeed)),
          if (snapshot.remainingBytes != null && snapshot.remainingBytes! > 0)
            stat(
              Icons.hourglass_bottom,
              '${formatBytes(snapshot.remainingBytes!)} left',
            ),
          if (snapshot.freeSpaceBytes != null && snapshot.freeSpaceBytes! > 0)
            stat(
              Icons.storage,
              '${formatBytes(snapshot.freeSpaceBytes!)} free',
            ),
          if (snapshot.paused) const StatusChip('Paused', color: Colors.orange),
        ],
      ),
    );
  }
}

Color stateColor(BuildContext context, DownloadState s) => switch (s) {
  DownloadState.downloading => Theme.of(context).colorScheme.primary,
  DownloadState.seeding || DownloadState.completed => Colors.green,
  DownloadState.paused => Colors.orange,
  DownloadState.error => Theme.of(context).colorScheme.error,
  DownloadState.checking || DownloadState.processing => Colors.blue,
  DownloadState.queued => Theme.of(context).colorScheme.outline,
};

class DownloadTile extends StatelessWidget {
  const DownloadTile({super.key, required this.item, this.onTap});
  final DownloadItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = stateColor(context, item.state);
    final details = [
      if (item.progress < 1 && item.sizeBytes > 0)
        '${formatBytes(item.sizeBytes - item.remainingBytes)} of ${formatBytes(item.sizeBytes)}'
      else if (item.sizeBytes > 0)
        formatBytes(item.sizeBytes),
      if (item.downSpeed > 0) '↓ ${formatSpeed(item.downSpeed)}',
      if (item.upSpeed > 0) '↑ ${formatSpeed(item.upSpeed)}',
      if (item.eta != null) formatEta(item.eta),
      if (item.ratio != null && item.progress >= 1)
        'ratio ${item.ratio!.toStringAsFixed(2)}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                StatusChip(item.state.label, color: color),
                const SizedBox(width: 8),
                Text(
                  '${(item.progress * 100).toStringAsFixed(item.progress < 1 ? 1 : 0)}%',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (item.category != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    item.category!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (item.state == DownloadState.error &&
                item.statusText != null) ...[
              const SizedBox(height: 4),
              Text(
                item.statusText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

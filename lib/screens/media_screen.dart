import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../state/nav_state.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'add_media_screen.dart';
import 'arr_queue_screen.dart';
import 'media_detail_screen.dart';
import 'servers_screen.dart';

enum _Filter { all, monitored, missing, unmonitored }

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  final _search = TextEditingController();
  String? _loadedFor;
  List<MediaItem>? _items;
  Object? _error;
  _Filter _filter = _Filter.all;
  bool _grid = true;

  ServerConfig? _current(BuildContext context) {
    final servers = context.read<ServerStore>().ofGroup(ServiceGroup.media);
    if (servers.isEmpty) return null;
    final id = context.read<NavState>().mediaId;
    return servers.where((s) => s.id == id).firstOrNull ?? servers.first;
  }

  Future<void> _load() async {
    final server = _current(context);
    if (server == null) return;
    final client = context.read<ServerStore>().client<ArrClient>(server);
    if (_loadedFor != server.id) {
      setState(() {
        _loadedFor = server.id;
        _items = null;
        _error = null;
      });
    }
    try {
      final items = await client.library();
      if (mounted && _loadedFor == server.id) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _loadedFor == server.id) setState(() => _error = e);
    }
  }

  bool _isMissing(MediaItem m, ServiceKind kind) => kind == ServiceKind.radarr
      ? m.monitored && !m.hasFile
      : m.monitored && m.totalCount > m.haveCount;

  List<MediaItem> _visible(ServiceKind kind) {
    final q = _search.text.trim().toLowerCase();
    return (_items ?? const <MediaItem>[]).where((m) {
      if (q.isNotEmpty && !m.title.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.monitored => m.monitored,
        _Filter.unmonitored => !m.monitored,
        _Filter.missing => _isMissing(m, kind),
      };
    }).toList();
  }

  Future<void> _open(ArrClient client, MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(client: client, item: item),
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    context.watch<NavState>();
    final servers = store.ofGroup(ServiceGroup.media);
    final server = _current(context);

    if (server != null && _loadedFor != server.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedFor != server.id) _load();
      });
    }

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Media')),
        body: NoServersView(
          what: 'Sonarr, Radarr or Lidarr',
          onAdd: () => addServer(context, group: ServiceGroup.media),
        ),
      );
    }

    final client = store.client<ArrClient>(server);
    final visible = _visible(server.kind);

    return Scaffold(
      appBar: AppBar(
        title: Text(server.name),
        actions: [
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.downloading),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ArrQueueScreen(client: client)),
            ),
          ),
          IconButton(
            tooltip: _grid ? 'List' : 'Grid',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add ${client.itemNoun}',
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddMediaScreen(client: client)),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          ServerPicker(
            servers: servers,
            selectedId: server.id,
            onSelected: (s) => context.read<NavState>().openMedia(s.id),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText:
                    'Filter ${_items?.length ?? ''} ${client.itemNoun == 'series' ? 'series' : '${client.itemNoun}s'}',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(switch (f) {
                        _Filter.all => 'All',
                        _Filter.monitored => 'Monitored',
                        _Filter.missing => 'Missing',
                        _Filter.unmonitored => 'Unmonitored',
                      }),
                      selected: _filter == f,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _error != null && _items == null
                ? ErrorView(error: _error!, onRetry: _load)
                : _items == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: visible.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              MessageView(
                                icon: Icons.search_off,
                                title: 'Nothing here',
                              ),
                            ],
                          )
                        : _grid
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 130,
                                  childAspectRatio: 0.52,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (_, i) => _PosterCard(
                              item: visible[i],
                              kind: server.kind,
                              missing: _isMissing(visible[i], server.kind),
                              onTap: () => _open(client, visible[i]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: visible.length,
                            itemBuilder: (_, i) => MediaListTile(
                              item: visible[i],
                              kind: server.kind,
                              onTap: () => _open(client, visible[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

String mediaProgressText(MediaItem m, ServiceKind kind) {
  if (kind == ServiceKind.radarr) {
    return m.hasFile
        ? 'Downloaded'
        : (m.monitored ? 'Missing' : 'Not monitored');
  }
  final noun = kind == ServiceKind.sonarr ? 'episodes' : 'tracks';
  return '${m.haveCount}/${m.totalCount} $noun';
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.kind,
    required this.missing,
    required this.onTap,
  });
  final MediaItem item;
  final ServiceKind kind;
  final bool missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = kind == ServiceKind.radarr
        ? item.hasFile
        : item.totalCount > 0 && item.haveCount >= item.totalCount;
    final barColor = !item.monitored
        ? theme.colorScheme.outline
        : complete
        ? Colors.green
        : missing
        ? Colors.redAccent
        : theme.colorScheme.primary;
    final fraction = kind == ServiceKind.radarr
        ? (item.hasFile ? 1.0 : 0.0)
        : item.totalCount == 0
        ? 0.0
        : item.haveCount / item.totalCount;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Poster(url: item.posterUrl, icon: kind.icon),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0, 1),
                      minHeight: 4,
                      color: barColor,
                      backgroundColor: Colors.black45,
                    ),
                  ),
                ),
                if (!item.monitored)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.bookmark_border,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          Text(
            mediaProgressText(item, kind),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class MediaListTile extends StatelessWidget {
  const MediaListTile({
    super.key,
    required this.item,
    required this.kind,
    this.onTap,
    this.trailing,
  });
  final MediaItem item;
  final ServiceKind kind;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Poster(
      url: item.posterUrl,
      width: 40,
      height: 60,
      icon: kind.icon,
    ),
    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        if (item.year != null) '${item.year}',
        if (item.inLibrary) mediaProgressText(item, kind),
        if (item.sizeOnDisk > 0) formatBytes(item.sizeOnDisk),
        if (!item.inLibrary && item.network != null) item.network!,
      ].join(' · '),
    ),
    trailing:
        trailing ??
        (item.inLibrary && !item.monitored
            ? const Icon(Icons.bookmark_border, size: 20)
            : null),
  );
}

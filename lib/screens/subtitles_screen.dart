import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/bazarr.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Bazarr: episodes and movies missing subtitles, and what it fetched lately.
class SubtitlesScreen extends StatefulWidget {
  const SubtitlesScreen({super.key});

  @override
  State<SubtitlesScreen> createState() => _SubtitlesScreenState();
}

class _SubtitlesScreenState extends State<SubtitlesScreen> {
  String? _serverId;
  List<WantedSubtitle>? _episodes;
  List<WantedSubtitle>? _movies;
  List<SubtitleEvent>? _history;
  Object? _error;
  final Set<String> _searching = {};

  ServerConfig? _server(ServerStore store) {
    final servers = store.ofKinds({ServiceKind.bazarr});
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
    final client = store.client<BazarrClient>(server);
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        client.wantedEpisodes(),
        client.wantedMovies(),
      ]);
      final history = await client.history();
      if (!mounted) return;
      setState(() {
        _episodes = results[0];
        _movies = results[1];
        _history = history;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _search(
    BazarrClient client,
    WantedSubtitle w,
    SubLanguage lang,
  ) async {
    final key = '${w.isMovie}${w.movieId}${w.episodeId}${lang.label}';
    setState(() => _searching.add(key));
    final ok = await runAction(
      context,
      () => client.searchMissing(w, lang),
      done: 'Searched ${lang.name} for ${w.title}',
    );
    if (!mounted) return;
    setState(() => _searching.remove(key));
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final server = _server(store);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subtitles')),
        body: NoServersView(
          what: 'Bazarr',
          onAdd: () => addServer(context, group: ServiceGroup.library),
        ),
      );
    }
    final client = store.client<BazarrClient>(server);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Subtitles'),
          actions: [
            IconButton(
              tooltip: 'Search all wanted',
              icon: const Icon(Icons.manage_search),
              onPressed: () => runAction(
                context,
                client.searchAllWanted,
                done: 'Bazarr is searching for everything missing',
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Series${_count(_episodes)}'),
              Tab(text: 'Movies${_count(_movies)}'),
              const Tab(text: 'History'),
            ],
          ),
        ),
        body: Column(
          children: [
            ServerPicker(
              servers: store.ofKinds({ServiceKind.bazarr}),
              selectedId: server.id,
              onSelected: (s) {
                setState(() {
                  _serverId = s.id;
                  _episodes = _movies = null;
                  _history = null;
                });
                _load();
              },
            ),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error!, onRetry: _load)
                  : TabBarView(
                      children: [
                        _wantedList(client, _episodes, 'episodes'),
                        _wantedList(client, _movies, 'movies'),
                        _historyList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _count(List<Object>? l) =>
      l == null || l.isEmpty ? '' : ' (${l.length})';

  Widget _wantedList(
    BazarrClient client,
    List<WantedSubtitle>? items,
    String noun,
  ) {
    if (items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                MessageView(
                  icon: Icons.subtitles_outlined,
                  title: 'Nothing missing',
                  body: 'Every one of your $noun has its subtitles.',
                ),
              ],
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final w = items[i];
                return ListTile(
                  title: Text(w.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (w.subtitle.isNotEmpty)
                        Text(
                          w.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final lang in w.missing)
                            _searching.contains(
                                  '${w.isMovie}${w.movieId}${w.episodeId}${lang.label}',
                                )
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : ActionChip(
                                    avatar: const Icon(Icons.search, size: 16),
                                    label: Text(lang.label),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _search(client, w, lang),
                                  ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _historyList() {
    final items = _history;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing yet.'),
            ),
          for (final e in items)
            ListTile(
              leading: Icon(e.isMovie ? Icons.movie_outlined : Icons.tv),
              title: Text(e.title),
              subtitle: Text(
                [
                  e.subtitle,
                  e.description,
                ].where((x) => x.isNotEmpty).join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(e.when, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

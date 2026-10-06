import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/comicarr.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Comicarr: the comics library, wanted issues and this week's releases.
class ComicsScreen extends StatefulWidget {
  const ComicsScreen({super.key});

  @override
  State<ComicsScreen> createState() => _ComicsScreenState();
}

class _ComicsScreenState extends State<ComicsScreen> {
  String? _serverId;
  List<ComicSeries>? _series;
  List<ComicRelease>? _wanted;
  List<ComicRelease>? _week;
  Object? _error;
  final Set<String> _searching = {};

  ServerConfig? _server(ServerStore store) {
    final servers = store.ofKinds({ServiceKind.comicarr});
    return servers.where((s) => s.id == _serverId).firstOrNull ??
        servers.firstOrNull;
  }

  ComicarrClient? _client(ServerStore store) {
    final s = _server(store);
    return s == null ? null : store.client<ComicarrClient>(s);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = _client(context.read<ServerStore>());
    if (client == null) return;
    setState(() => _error = null);
    try {
      final series = await client.series();
      if (mounted) setState(() => _series = series);
      final wanted = await client.wanted();
      final week = await client.thisWeek();
      if (!mounted) return;
      setState(() {
        _wanted = wanted;
        _week = week;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _search(ComicarrClient client, ComicRelease r) async {
    setState(() => _searching.add(r.issueId));
    await runAction(
      context,
      () => client.searchIssue(r.issueId),
      done: 'Searching for ${r.label}',
    );
    if (mounted) setState(() => _searching.remove(r.issueId));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final client = _client(store);
    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comics')),
        body: NoServersView(
          what: 'Comicarr',
          onAdd: () => addServer(context, group: ServiceGroup.other),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comics'),
          actions: [
            IconButton(
              tooltip: 'Add a series',
              icon: const Icon(Icons.add),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AddComicScreen(client: client),
                  ),
                );
                _load();
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Library'),
              Tab(
                text:
                    'Wanted${(_wanted?.isNotEmpty ?? false) ? ' (${_wanted!.length})' : ''}',
              ),
              const Tab(text: 'This week'),
            ],
          ),
        ),
        body: Column(
          children: [
            ServerPicker(
              servers: store.ofKinds({ServiceKind.comicarr}),
              selectedId: _server(store)?.id,
              onSelected: (s) {
                setState(() {
                  _serverId = s.id;
                  _series = null;
                  _wanted = _week = null;
                });
                _load();
              },
            ),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error!, onRetry: _load)
                  : TabBarView(
                      children: [
                        _library(client),
                        _releases(client, _wanted, wanted: true),
                        _releases(client, _week, wanted: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _library(ComicarrClient client) {
    final series = _series;
    if (series == null) return const Center(child: CircularProgressIndicator());
    if (series.isEmpty) {
      return const MessageView(
        icon: Icons.auto_stories_outlined,
        title: 'No series yet',
        body: 'Add one with the + button.',
      );
    }
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.48,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
        ),
        itemCount: series.length,
        itemBuilder: (context, i) {
          final s = series[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _ComicSeriesScreen(client: client, seriesId: s.id),
                ),
              );
              _load();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(
                        url: s.coverUrl,
                        icon: Icons.auto_stories_outlined,
                        headers: client.imageHeaders,
                      ),
                      if (s.paused)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: StatusChip('Paused'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${s.have} / ${s.total}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: s.completion,
                  minHeight: 3,
                  color: s.completion >= 1 ? Colors.green : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _releases(
    ComicarrClient client,
    List<ComicRelease>? items, {
    required bool wanted,
  }) {
    if (items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                MessageView(
                  icon: Icons.auto_stories_outlined,
                  title: wanted ? 'Nothing wanted' : 'Nothing out this week',
                  body: wanted
                      ? 'Every issue you want is downloaded.'
                      : 'No new issues for series in your library.',
                ),
              ],
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = items[i];
                return ListTile(
                  title: Text(r.label),
                  subtitle: Text(
                    [r.name, r.date].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _searching.contains(r.issueId)
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : r.status == 'Wanted' && r.issueId.isNotEmpty
                      ? IconButton(
                          tooltip: 'Search now',
                          icon: const Icon(Icons.search),
                          onPressed: () => _search(client, r),
                        )
                      : StatusChip(r.status, color: _stateColor(r.status)),
                );
              },
            ),
    );
  }
}

Color? _stateColor(String state) => switch (state) {
  'Downloaded' || 'Archived' => Colors.green,
  'Snatched' || 'Reserved' => Colors.blue,
  'Wanted' || 'Missing' => Colors.orange,
  'Failed' => Colors.red,
  _ => null,
};

class _ComicSeriesScreen extends StatefulWidget {
  const _ComicSeriesScreen({required this.client, required this.seriesId});
  final ComicarrClient client;
  final String seriesId;

  @override
  State<_ComicSeriesScreen> createState() => _ComicSeriesScreenState();
}

class _ComicSeriesScreenState extends State<_ComicSeriesScreen> {
  ComicSeries? _series;
  List<ComicIssue> _issues = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (series, issues) = await widget.client.seriesDetail(
        widget.seriesId,
      );
      if (!mounted) return;
      setState(() {
        _series = series;
        _issues = issues;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _searchMissing() async {
    try {
      final n = await widget.client.searchMissing(widget.seriesId);
      if (!mounted) return;
      showMessage(
        context,
        n == 0
            ? 'Nothing missing to search for'
            : 'Searching for $n issue${n == 1 ? '' : 's'}',
      );
      _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _series;
    final theme = Theme.of(context);
    final client = widget.client;
    return Scaffold(
      appBar: AppBar(title: Text(s?.name ?? 'Series')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Poster(
                          url: s.coverUrl,
                          width: 100,
                          height: 150,
                          icon: Icons.auto_stories_outlined,
                          headers: client.imageHeaders,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  s.year,
                                  s.publisher,
                                ].where((x) => x.isNotEmpty).join(' · '),
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              StatusChip(
                                s.status,
                                color: s.paused ? null : Colors.green,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${s.have} of ${s.total} issues',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: s.completion),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _searchMissing,
                          icon: const Icon(Icons.search),
                          label: const Text('Search missing'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (await runAction(
                              context,
                              () => client.refresh(s.id),
                              done: 'Refreshing ${s.name}',
                            )) {
                              _load();
                            }
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (await runAction(
                              context,
                              () => client.setPaused(s.id, !s.paused),
                              done: s.paused ? 'Resumed' : 'Paused',
                            )) {
                              _load();
                            }
                          },
                          icon: Icon(s.paused ? Icons.play_arrow : Icons.pause),
                          label: Text(s.paused ? 'Resume' : 'Pause'),
                        ),
                      ],
                    ),
                  ),
                  if (s.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(
                        s.description.replaceAll(RegExp(r'<[^>]*>'), ''),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SectionHeader('Issues'),
                  for (final issue in _issues)
                    ListTile(
                      title: Text(
                        [
                          '#${issue.number}',
                          if (issue.name.isNotEmpty) issue.name,
                        ].join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: issue.releaseDate.isEmpty
                          ? null
                          : Text(issue.releaseDate),
                      trailing: StatusChip(
                        issue.state,
                        color: _stateColor(issue.state),
                      ),
                      onTap: () => _issueActions(issue),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _issueActions(ComicIssue issue) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: Text('Search for #${issue.number}'),
              subtitle: const Text('Marks it wanted and searches now'),
              onTap: () => Navigator.pop(context, 'search'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Skip this issue'),
              onTap: () => Navigator.pop(context, 'skip'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final client = widget.client;
    if (await runAction(
      context,
      () => action == 'search'
          ? client.searchIssue(issue.id)
          : client.skipIssue(issue.id),
      done: action == 'search'
          ? 'Searching for #${issue.number}'
          : 'Skipped #${issue.number}',
    )) {
      _load();
    }
  }
}

class _AddComicScreen extends StatefulWidget {
  const _AddComicScreen({required this.client});
  final ComicarrClient client;

  @override
  State<_AddComicScreen> createState() => _AddComicScreenState();
}

class _AddComicScreenState extends State<_AddComicScreen> {
  final _query = TextEditingController();
  List<ComicSearchResult>? _results;
  Object? _error;
  bool _loading = false;
  final Set<String> _added = {};

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.client.search(q);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a series')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Series name',
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? ErrorView(error: _error!, onRetry: _search)
              : _results != null && _results!.isEmpty
              ? const MessageView(
                  icon: Icons.search_off,
                  title: 'No matches',
                  body: 'Try a shorter name, or leave out the year.',
                )
              : ListView(
                  children: [
                    for (final r in _results ?? const <ComicSearchResult>[])
                      ListTile(
                        leading: Poster(
                          url: r.coverUrl,
                          width: 40,
                          height: 60,
                          icon: Icons.auto_stories_outlined,
                        ),
                        title: Text(
                          [
                            r.name,
                            if (r.year.isNotEmpty) '(${r.year})',
                          ].join(' '),
                        ),
                        subtitle: Text(
                          [
                            r.publisher,
                            if (r.issues > 0) '${r.issues} issues',
                          ].where((x) => x.isNotEmpty).join(' · '),
                        ),
                        trailing: r.inLibrary || _added.contains(r.id)
                            ? const StatusChip(
                                'In library',
                                color: Colors.green,
                              )
                            : IconButton(
                                tooltip: 'Add',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () async {
                                  if (await runAction(
                                    context,
                                    () => widget.client.add(r),
                                    done: 'Adding ${r.name}',
                                  )) {
                                    setState(() => _added.add(r.id));
                                  }
                                },
                              ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

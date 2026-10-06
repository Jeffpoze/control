import 'package:flutter/material.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'media_edit_screen.dart';
import 'release_search_screen.dart';

class MediaDetailScreen extends StatefulWidget {
  const MediaDetailScreen({
    super.key,
    required this.client,
    required this.item,
  });
  final ArrClient client;
  final MediaItem item;

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  late MediaItem _item = widget.item;
  List<Episode>? _episodes;
  Object? _episodeError;

  ArrClient get client => widget.client;
  bool get isSonarr => client.kind == ServiceKind.sonarr;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final item = await client.item(_item.id);
      if (mounted) setState(() => _item = item);
    } catch (_) {}
    if (isSonarr) {
      try {
        final eps = await client.episodes(_item.id);
        if (mounted) setState(() => _episodes = eps);
      } catch (e) {
        if (mounted) setState(() => _episodeError = e);
      }
    }
  }

  Future<void> _editItem() async {
    final updated = await Navigator.of(context).push<MediaItem>(
      MaterialPageRoute(
        builder: (_) => MediaEditScreen(client: client, item: _item),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _item = updated);
      showMessage(context, 'Saved');
    }
  }

  void _chooseRelease({
    int? movieId,
    int? episodeId,
    int? seasonNumber,
    String? title,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReleaseSearchScreen(
        client: client,
        title: title ?? _item.title,
        movieId: movieId,
        episodeId: episodeId,
        seriesId: seasonNumber == null ? null : _item.id,
        seasonNumber: seasonNumber,
      ),
    ),
  );

  Future<void> _toggleMonitored() async {
    await runAction(context, () async {
      final updated = await client.setMonitored(_item, !_item.monitored);
      if (mounted) setState(() => _item = updated);
    });
  }

  Future<void> _delete() async {
    var deleteFiles = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Delete ${_item.title}?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteFiles,
            onChanged: (v) => setLocal(() => deleteFiles = v ?? false),
            title: const Text('Also delete files from disk'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAction(
      context,
      () => client.delete(_item, deleteFiles: deleteFiles),
      done: 'Deleted ${_item.title}',
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    final seasons = isSonarr
        ? ((item.raw['seasons'] as List?) ?? const [])
              .cast<Map>()
              .map((s) => s.cast<String, dynamic>())
              .toList()
              .reversed
              .toList()
        : const <Map<String, dynamic>>[];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: item.fanartUrl != null ? 200 : null,
              flexibleSpace: item.fanartUrl == null
                  ? null
                  : FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            item.fanartUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  theme.scaffoldBackgroundColor,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              actions: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.tune),
                  onPressed: _editItem,
                ),
                IconButton(
                  tooltip: item.monitored ? 'Stop monitoring' : 'Monitor',
                  icon: Icon(
                    item.monitored ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: _toggleMonitored,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'refresh':
                        runAction(
                          context,
                          () => client.refresh(item),
                          done: 'Refreshing ${item.title}',
                        );
                      case 'delete':
                        _delete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh and scan'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete…')),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Poster(
                      url: item.posterUrl,
                      width: 110,
                      height: 165,
                      icon: client.kind.icon,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (item.year != null) '${item.year}',
                              ?item.network,
                              if (item.status.isNotEmpty) _cap(item.status),
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              StatusChip(
                                item.monitored ? 'Monitored' : 'Not monitored',
                                color: item.monitored
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              if (client.kind == ServiceKind.radarr)
                                StatusChip(
                                  item.hasFile ? 'Downloaded' : 'Missing',
                                  color: item.hasFile
                                      ? Colors.green
                                      : Colors.redAccent,
                                )
                              else
                                StatusChip(
                                  '${item.haveCount}/${item.totalCount}',
                                  color: item.haveCount >= item.totalCount
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              if (item.sizeOnDisk > 0)
                                StatusChip(formatBytes(item.sizeOnDisk)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => runAction(
                              context,
                              () => client.searchItem(item),
                              done: 'Searching for ${item.title}',
                            ),
                            icon: const Icon(Icons.search),
                            label: Text(
                              client.kind == ServiceKind.radarr
                                  ? 'Search for movie'
                                  : 'Search for missing',
                            ),
                          ),
                          if (client.kind == ServiceKind.radarr) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _chooseRelease(movieId: item.id),
                              icon: const Icon(Icons.manage_search),
                              label: const Text('Choose a release'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (item.overview.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(item.overview, style: theme.textTheme.bodyMedium),
                ),
              ),
            if (client.kind == ServiceKind.radarr) _movieFile(theme),
            if (isSonarr) ..._seasonSlivers(seasons),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  Widget _movieFile(ThemeData theme) {
    final file = (_item.raw['movieFile'] as Map?)?.cast<String, dynamic>();
    if (file == null) return const SliverToBoxAdapter(child: SizedBox());
    final quality = ((file['quality'] as Map?)?['quality'] as Map?)?['name'];
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('File'),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(
              (file['relativePath'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (quality != null) '$quality',
                formatBytes(asInt(file['size'])),
              ].join(' · '),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _seasonSlivers(List<Map<String, dynamic>> seasons) {
    if (_episodeError != null) {
      return [
        SliverToBoxAdapter(
          child: ErrorView(error: _episodeError!, onRetry: _reload),
        ),
      ];
    }
    if (_episodes == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    return [
      const SliverToBoxAdapter(child: SectionHeader('Seasons')),
      SliverList.list(
        children: [
          for (final s in seasons)
            _SeasonTile(
              season: s,
              episodes:
                  _episodes!
                      .where((e) => e.season == asInt(s['seasonNumber']))
                      .toList()
                    ..sort((a, b) => b.number.compareTo(a.number)),
              client: client,
              seriesId: _item.id,
              onChooseRelease: (season, episode) => _chooseRelease(
                seasonNumber: episode == null ? season : null,
                episodeId: episode?.id,
                title: episode == null
                    ? '${_item.title} · Season $season'
                    : '${_item.title} · ${episode.code}',
              ),
              onToggleSeason: (monitored) => runAction(context, () async {
                final updated = await client.setSeasonMonitored(
                  _item,
                  asInt(s['seasonNumber']),
                  monitored,
                );
                if (mounted) setState(() => _item = updated);
                await _reload();
              }),
              onChanged: _reload,
            ),
        ],
      ),
    ];
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _SeasonTile extends StatelessWidget {
  const _SeasonTile({
    required this.season,
    required this.episodes,
    required this.client,
    required this.seriesId,
    required this.onToggleSeason,
    required this.onChanged,
    required this.onChooseRelease,
  });

  final Map<String, dynamic> season;
  final List<Episode> episodes;
  final ArrClient client;
  final int seriesId;
  final ValueChanged<bool> onToggleSeason;
  final Future<void> Function() onChanged;

  /// Interactive search for the season (episode null) or one episode.
  final void Function(int season, Episode? episode) onChooseRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = asInt(season['seasonNumber']);
    final monitored = season['monitored'] == true;
    final aired = episodes
        .where((e) => e.airDate != null && e.airDate!.isBefore(DateTime.now()))
        .toList();
    final have = episodes.where((e) => e.hasFile).length;
    return ExpansionTile(
      title: Text(number == 0 ? 'Specials' : 'Season $number'),
      subtitle: Text('$have of ${aired.length} aired episodes'),
      leading: IconButton(
        tooltip: monitored ? 'Stop monitoring season' : 'Monitor season',
        icon: Icon(
          monitored ? Icons.bookmark : Icons.bookmark_border,
          color: monitored ? theme.colorScheme.primary : null,
        ),
        onPressed: () => onToggleSeason(!monitored),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Choose a release for this season',
            icon: const Icon(Icons.manage_search),
            onPressed: () => onChooseRelease(number, null),
          ),
          IconButton(
            tooltip: 'Search season',
            icon: const Icon(Icons.search),
            onPressed: () => runAction(
              context,
              () => client.searchSeason(seriesId, number),
              done: 'Searching season $number',
            ),
          ),
        ],
      ),
      children: [
        for (final e in episodes)
          ListTile(
            dense: true,
            onLongPress: () => onChooseRelease(number, e),
            leading: Icon(
              e.hasFile
                  ? Icons.check_circle
                  : (e.airDate?.isAfter(DateTime.now()) ?? true)
                  ? Icons.schedule
                  : Icons.radio_button_unchecked,
              color: e.hasFile
                  ? Colors.green
                  : e.monitored &&
                        (e.airDate?.isBefore(DateTime.now()) ?? false)
                  ? Colors.redAccent
                  : theme.colorScheme.outline,
              size: 20,
            ),
            title: Text(
              '${e.number}. ${e.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: e.airDate == null ? null : Text(formatDay(e.airDate!)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    e.monitored ? Icons.bookmark : Icons.bookmark_border,
                    size: 20,
                  ),
                  onPressed: () async {
                    if (await runAction(
                      context,
                      () => client.setEpisodesMonitored([e.id], !e.monitored),
                    )) {
                      await onChanged();
                    }
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Choose a release',
                  icon: const Icon(Icons.manage_search, size: 20),
                  onPressed: () => onChooseRelease(number, e),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => runAction(
                    context,
                    () => client.searchEpisodes([e.id]),
                    done: 'Searching ${e.code}',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

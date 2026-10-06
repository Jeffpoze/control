import 'package:flutter/material.dart';

import '../services/arr.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Interactive search: asks every indexer through Sonarr, Radarr or Lidarr
/// and lets you pick the exact release to download.
class ReleaseSearchScreen extends StatefulWidget {
  const ReleaseSearchScreen({
    super.key,
    required this.client,
    required this.title,
    this.movieId,
    this.episodeId,
    this.seriesId,
    this.seasonNumber,
    this.albumId,
  });

  final ArrClient client;
  final String title;
  final int? movieId;
  final int? episodeId;
  final int? seriesId;
  final int? seasonNumber;
  final int? albumId;

  @override
  State<ReleaseSearchScreen> createState() => _ReleaseSearchScreenState();
}

class _ReleaseSearchScreenState extends State<ReleaseSearchScreen> {
  List<ArrRelease>? _releases;
  Object? _error;
  bool _showRejected = false;
  final Set<String> _grabbed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _releases = null;
    });
    try {
      final r = await widget.client.releases(
        movieId: widget.movieId,
        episodeId: widget.episodeId,
        seriesId: widget.seriesId,
        seasonNumber: widget.seasonNumber,
        albumId: widget.albumId,
      );
      if (mounted) setState(() => _releases = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _grab(ArrRelease r) async {
    final ok = await confirm(
      context,
      title: 'Download this release?',
      body: [
        r.title,
        if (r.rejected)
          '\n${widget.client.kind.label} would normally skip it: '
              '${r.rejections.join('; ')}',
      ].join('\n'),
      action: 'Download',
      destructive: false,
    );
    if (!ok || !mounted) return;
    if (await runAction(
      context,
      () => widget.client.grab(r),
      done: 'Sent to the download client',
    )) {
      setState(() => _grabbed.add(r.guid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _releases;
    final shown = all?.where((r) => _showRejected || !r.rejected).toList();
    final hidden = (all?.length ?? 0) - (shown?.length ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Search again',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : shown == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Asking your indexers…'),
                ],
              ),
            )
          : ListView(
              children: [
                if (hidden > 0 || _showRejected)
                  SwitchListTile(
                    title: Text(
                      'Show releases that would be skipped ($hidden)',
                    ),
                    value: _showRejected,
                    onChanged: (v) => setState(() => _showRejected = v),
                  ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: MessageView(
                      icon: Icons.search_off,
                      title: 'No releases found',
                    ),
                  ),
                for (final r in shown)
                  _ReleaseTile(
                    release: r,
                    grabbed: _grabbed.contains(r.guid),
                    onTap: () => _grab(r),
                  ),
              ],
            ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.grabbed,
    required this.onTap,
  });
  final ArrRelease release;
  final bool grabbed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = release;
    final age = r.ageDays;
    return ListTile(
      onTap: grabbed ? null : onTap,
      title: Text(
        r.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: r.rejected ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (r.quality.isNotEmpty)
                StatusChip(r.quality, color: theme.colorScheme.primary),
              StatusChip(formatBytes(r.size)),
              if (r.customFormatScore != 0)
                StatusChip(
                  'Score ${r.customFormatScore}',
                  color: r.customFormatScore > 0 ? Colors.green : Colors.orange,
                ),
              for (final l in r.languages.take(2)) StatusChip(l),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              r.indexer,
              if (r.isTorrent) '${r.seeders} seeders' else 'Usenet',
              if (age > 0)
                age < 1
                    ? '${(age * 24).round()} h old'
                    : '${age.round()} days old',
            ].where((x) => x.isNotEmpty).join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (r.rejected)
            Text(
              r.rejections.join('; '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      trailing: grabbed
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.download_outlined),
      isThreeLine: true,
    );
  }
}

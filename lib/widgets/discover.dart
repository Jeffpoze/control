import 'dart:async';

import 'package:flutter/material.dart';

import '../services/arr.dart';
import '../services/overseerr.dart';
import '../util/format.dart';
import 'common.dart';

/// Full-width artwork that fades in, with a flat colour behind it.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, this.url, this.fallbackUrl});
  final String? url;
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    final bg = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    final src = url ?? fallbackUrl;
    if (src == null) return bg;
    return Image.network(
      src,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => bg,
      frameBuilder: (_, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: child,
            ),
    );
  }
}

/// A dark gradient so white text reads on any artwork.
const _scrim = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0x33000000), Color(0xDD000000)],
      stops: [0.3, 0.55, 1],
    ),
  ),
);

/// The big swiping banner at the top of Home: what's trending right now.
class TrendingBanner extends StatefulWidget {
  const TrendingBanner({super.key, required this.items, required this.onTap});
  final List<DiscoverResult> items;
  final void Function(DiscoverResult) onTap;

  @override
  State<TrendingBanner> createState() => _TrendingBannerState();
}

class _TrendingBannerState extends State<TrendingBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) => _advance());
  }

  void _advance() {
    if (!mounted || !_controller.hasClients || widget.items.length < 2) return;
    final next = (_page + 1) % widget.items.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: PageView.builder(
            controller: _controller,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BannerCard(
                item: items[i],
                rank: i + 1,
                onTap: () => widget.onTap(items[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Dots(count: items.length, index: _page),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.item,
    required this.rank,
    required this.onTap,
  });
  final DiscoverResult item;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.availabilityLabel;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Backdrop(url: item.backdropUrl, fallbackUrl: item.posterUrl),
            _scrim,
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#$rank TRENDING · ${item.isTv ? 'SERIES' : 'MOVIE'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.year != null)
                        _Meta('${item.year}', color: Colors.white70),
                      if (item.rating > 0)
                        _Meta(
                          '★ ${item.rating.toStringAsFixed(1)}',
                          color: Colors.amber.shade300,
                        ),
                      if (status.isNotEmpty)
                        StatusChip(
                          status,
                          color: status == 'Available'
                              ? Colors.greenAccent
                              : Colors.lightBlueAccent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? c.primary : c.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A sideways-scrolling row of posters (popular movies, upcoming…).
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.items, required this.onTap});
  final List<DiscoverResult> items;
  final void Function(DiscoverResult) onTap;

  static const _width = 112.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _width * 1.5 + 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final r = items[i];
          return SizedBox(
            width: _width,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTap(r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Poster(
                        url: r.posterUrl,
                        width: _width,
                        height: _width * 1.5,
                        icon: r.isTv ? Icons.tv : Icons.movie_outlined,
                      ),
                      if (r.availability >= 2)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _AvailabilityBadge(r.availability),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge(this.availability);
  final int availability;

  @override
  Widget build(BuildContext context) {
    final available = availability >= 4;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: available ? Colors.green : Colors.blue,
        shape: BoxShape.circle,
      ),
      child: Icon(
        available ? Icons.check : Icons.schedule,
        size: 12,
        color: Colors.white,
      ),
    );
  }
}

/// Sideways strip of what Sonarr, Radarr and Lidarr are downloading now.
class NowDownloadingStrip extends StatelessWidget {
  const NowDownloadingStrip({super.key, required this.items, this.onTap});
  final List<ActiveDownload> items;
  final void Function(ActiveDownload)? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) => _ActiveCard(
        item: items[i],
        onTap: onTap == null ? null : () => onTap!(items[i]),
      ),
    ),
  );
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.item, this.onTap});
  final ActiveDownload item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (item.progress * 100).round();
    final eta = formatEta(item.timeLeft);
    final state = item.hasWarning
        ? 'Needs attention'
        : item.isDownloading
        ? ['$pct%', if (eta.isNotEmpty) '$eta left'].join(' · ')
        : _statusLabel(item.status);
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Backdrop(url: item.fanartUrl),
              const ColoredBox(color: Color(0xAA000000)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Poster(
                      url: item.posterUrl,
                      width: 64,
                      height: 96,
                      icon: item.kind.icon,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty)
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              minHeight: 5,
                              backgroundColor: Colors.white24,
                              color: item.hasWarning
                                  ? Colors.orangeAccent
                                  : item.isDownloading
                                  ? theme.colorScheme.primary
                                  : Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            state,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: item.hasWarning
                                  ? Colors.orangeAccent
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
    'paused' => 'Paused',
    'queued' => 'Queued',
    'delay' => 'Waiting (delay profile)',
    'completed' => 'Importing',
    'downloadclientunavailable' => 'Download client unreachable',
    '' => 'Waiting',
    _ => s[0].toUpperCase() + s.substring(1),
  };
}

/// Details for a trending or popular title, with a Request button when
/// Overseerr is set up. Returns true when a request was made.
Future<bool> showDiscoverSheet(
  BuildContext context,
  OverseerrClient? client,
  DiscoverResult r,
) async {
  final requested = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    builder: (context) => _DiscoverSheet(client: client, item: r),
  );
  return requested ?? false;
}

class _DiscoverSheet extends StatefulWidget {
  const _DiscoverSheet({required this.client, required this.item});
  final OverseerrClient? client;
  final DiscoverResult item;

  @override
  State<_DiscoverSheet> createState() => _DiscoverSheetState();
}

class _DiscoverSheetState extends State<_DiscoverSheet> {
  bool _busy = false;
  late DiscoverResult _item = widget.item;

  /// Titles straight from TMDB don't say whether they're already requested
  /// or available, so ask Overseerr.
  late bool _checking =
      widget.client != null && widget.item.raw['mediaInfo'] == null;

  @override
  void initState() {
    super.initState();
    if (_checking) _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final r = await widget.client!.withStatus(widget.item);
      if (mounted) setState(() => _item = r);
    } catch (_) {
      // Unknown status: still offer the request; Overseerr will say if not.
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final r = _item;
    final ok = await runAction(
      context,
      () => widget.client!.submitRequest(r),
      done: 'Requested ${r.title}',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _item;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Backdrop(url: r.backdropUrl, fallbackUrl: r.posterUrl),
                  _scrim,
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Text(
                      r.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                [
                  r.isTv ? 'Series' : 'Movie',
                  if (r.year != null) '${r.year}',
                  if (r.rating > 0) '★ ${r.rating.toStringAsFixed(1)}',
                ].join(' · '),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (r.overview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(r.overview, style: theme.textTheme.bodyMedium),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: widget.client == null
                  ? Text(
                      'Add Overseerr or Jellyseerr under Servers to request '
                      'titles from here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : _checking
                  ? const Center(child: CircularProgressIndicator())
                  : r.canRequest
                  ? FilledButton.icon(
                      onPressed: _busy ? null : _request,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(r.isTv ? 'Request all seasons' : 'Request'),
                    )
                  : FilledButton.tonal(
                      onPressed: null,
                      child: Text(
                        r.availabilityLabel.isEmpty
                            ? 'Can\'t be requested'
                            : r.availabilityLabel,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

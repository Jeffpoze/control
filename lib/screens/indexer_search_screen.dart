import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/download_client.dart';
import '../services/prowlarr.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

enum _Protocol { all, usenet, torrent }

/// Search every Prowlarr indexer and send a release to a download client.
class IndexerSearchScreen extends StatefulWidget {
  const IndexerSearchScreen({super.key});

  @override
  State<IndexerSearchScreen> createState() => _IndexerSearchScreenState();
}

class _IndexerSearchScreenState extends State<IndexerSearchScreen> {
  final _query = TextEditingController();
  List<Release>? _results;
  Object? _error;
  bool _searching = false;
  _Protocol _protocol = _Protocol.all;

  ServerConfig? _server(ServerStore s) =>
      s.ofKinds({ServiceKind.prowlarr}).firstOrNull;

  Future<void> _search() async {
    final q = _query.text.trim();
    final store = context.read<ServerStore>();
    final server = _server(store);
    if (q.isEmpty || server == null) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await store.client<ProwlarrClient>(server).search(q);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send(Release r) async {
    final store = context.read<ServerStore>();
    final prowlarr = store.client<ProwlarrClient>(_server(store)!);
    final clients = store.ofKinds(
      r.isTorrent
          ? {ServiceKind.qbittorrent, ServiceKind.transmission}
          : {ServiceKind.sabnzbd, ServiceKind.nzbget},
    );
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                r.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: Icon(ServiceKind.prowlarr.icon),
              title: const Text('Grab with Prowlarr'),
              subtitle: const Text(
                'Uses the download client set up in Prowlarr',
              ),
              onTap: () => Navigator.pop(sheet, 'prowlarr'),
            ),
            for (final c in clients)
              if (r.downloadUrl != null)
                ListTile(
                  leading: Icon(c.kind.icon),
                  title: Text('Send to ${c.name}'),
                  onTap: () => Navigator.pop(sheet, c),
                ),
            if (r.downloadUrl != null)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy link'),
                onTap: () => Navigator.pop(sheet, 'copy'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'prowlarr') {
      await runAction(context, () => prowlarr.grab(r), done: 'Grabbed');
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: r.downloadUrl!));
      if (mounted) showMessage(context, 'Link copied');
    } else if (choice is ServerConfig) {
      await runAction(
        context,
        () => store.client<DownloadClient>(choice).addUrl(r.downloadUrl!),
        done: 'Sent to ${choice.name}',
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    if (_server(store) == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Search indexers')),
        body: NoServersView(
          what: 'Prowlarr',
          onAdd: () => addServer(context, group: ServiceGroup.indexer),
        ),
      );
    }
    final theme = Theme.of(context);
    final visible = (_results ?? const <Release>[])
        .where(
          (r) => switch (_protocol) {
            _Protocol.all => true,
            _Protocol.usenet => !r.isTorrent,
            _Protocol.torrent => r.isTorrent,
          },
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Search indexers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search all indexers',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_results != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_Protocol>(
                segments: const [
                  ButtonSegment(value: _Protocol.all, label: Text('All')),
                  ButtonSegment(value: _Protocol.usenet, label: Text('Usenet')),
                  ButtonSegment(
                    value: _Protocol.torrent,
                    label: Text('Torrent'),
                  ),
                ],
                selected: {_protocol},
                onSelectionChanged: (v) => setState(() => _protocol = v.first),
              ),
            ),
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _search)
                : _results == null
                ? const SizedBox()
                : visible.isEmpty
                ? const MessageView(icon: Icons.search_off, title: 'No results')
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final r = visible[i];
                      return ListTile(
                        onTap: () => _send(r),
                        title: Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          [
                            r.indexer,
                            formatBytes(r.size),
                            if (r.published != null) formatAgo(r.published!),
                            if (r.seeders != null)
                              '${r.seeders} seeders'
                            else if (r.grabs > 0)
                              '${r.grabs} grabs',
                          ].join(' · '),
                        ),
                        trailing: StatusChip(
                          r.isTorrent ? 'Torrent' : 'Usenet',
                          color: r.isTorrent ? Colors.purple : Colors.blue,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

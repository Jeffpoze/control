import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../state/server_store.dart';
import 'server_edit_screen.dart';

const groupLabels = {
  ServiceGroup.downloader: 'Download clients',
  ServiceGroup.media: 'TV, movies and music',
  ServiceGroup.indexer: 'Indexers',
  ServiceGroup.other:
      'Requests, streaming, subtitles, comics and notifications',
};

/// Opens the "what kind of server?" sheet, then the editor.
Future<void> addServer(BuildContext context, {ServiceGroup? group}) async {
  final kind = await showModalBottomSheet<ServiceKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final g in ServiceGroup.values)
            if (group == null || group == g) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  groupLabels[g]!,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final k in ServiceKind.values.where((k) => k.group == g))
                ListTile(
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(context, k),
                ),
            ],
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ServerEditScreen(kind: kind),
      fullscreenDialog: true,
    ),
  );
}

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addServer(context),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
      body: store.servers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Add your download clients, Sonarr, Radarr and the rest. '
                  'Each one can have a home address and an away address; '
                  'Control switches between them on its own.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final g in ServiceGroup.values)
                  if (store.ofGroup(g).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        groupLabels[g]!,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    for (final s in store.ofGroup(g))
                      ListTile(
                        leading: Icon(s.kind.icon),
                        title: Text(s.name),
                        subtitle: Text(
                          [
                            s.kind.label,
                            s.localUrl,
                            s.remoteUrl,
                          ].where((x) => x.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ServerEditScreen(kind: s.kind, existing: s),
                          ),
                        ),
                      ),
                  ],
              ],
            ),
    );
  }
}

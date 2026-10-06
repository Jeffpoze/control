import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';
import 'server_edit_screen.dart';

const groupLabels = {
  ServiceGroup.mediaServer: 'Media servers',
  ServiceGroup.downloader: 'Download clients',
  ServiceGroup.media: 'TV, movies and music',
  ServiceGroup.library: 'Subtitles and comics',
  ServiceGroup.indexer: 'Indexers',
  ServiceGroup.requests: 'Requests and discovery',
  ServiceGroup.notifications: 'Notifications',
};

/// What the add button in each section says.
const addLabels = {
  ServiceGroup.mediaServer: 'Add a media server',
  ServiceGroup.downloader: 'Add a download client',
  ServiceGroup.media: 'Add Sonarr, Radarr or Lidarr',
  ServiceGroup.library: 'Add Bazarr or Comicarr',
  ServiceGroup.indexer: 'Add an indexer',
  ServiceGroup.requests: 'Add Overseerr or TMDB',
  ServiceGroup.notifications: 'Add an ntfy server',
};

/// The kinds in a section, for the hint under its add button.
String groupKinds(ServiceGroup g) => ServiceKind.values
    .where((k) => k.group == g)
    .map((k) => k == ServiceKind.tautulli ? 'Plex (Tautulli)' : k.label)
    .join(', ');

/// Opens the "what kind of server?" sheet, then the editor.
Future<void> addServer(BuildContext context, {ServiceGroup? group}) async {
  final only = group == null
      ? const <ServiceKind>[]
      : ServiceKind.values.where((k) => k.group == group).toList();
  final kind = only.length == 1
      ? only.single
      : await showModalBottomSheet<ServiceKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final g in groupLabels.keys)
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
                  subtitle: k == ServiceKind.tautulli
                      ? const Text('For Plex')
                      : null,
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Each server can have a home address and an away address; '
              'Control switches between them on its own.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final g in groupLabels.keys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(groupLabels[g]!, style: theme.textTheme.labelLarge),
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
                    builder: (_) => ServerEditScreen(kind: s.kind, existing: s),
                  ),
                ),
              ),
            ListTile(
              leading: Icon(Icons.add, color: theme.colorScheme.primary),
              title: Text(
                addLabels[g]!,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              subtitle: Text(groupKinds(g)),
              onTap: () => addServer(context, group: g),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
            child: Text('Backup', style: theme.textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Your setup stays on this phone when you update Control. To move '
              'it to another phone, or keep a copy, copy a backup and paste it '
              'there.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Copy a backup'),
            subtitle: const Text('Every server, with its keys and passwords'),
            enabled: store.servers.isNotEmpty,
            onTap: () => _copyBackup(context, store),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_go_outlined),
            title: const Text('Restore from a copied backup'),
            onTap: () => _restoreBackup(context, store),
          ),
        ],
      ),
    );
  }

  Future<void> _copyBackup(BuildContext context, ServerStore store) async {
    final ok = await confirm(
      context,
      title: 'Copy a backup?',
      body:
          'The backup includes your API keys and passwords as plain text. '
          'Paste it only somewhere private, like a note on your own phone, '
          'and delete it once restored.',
      action: 'Copy',
      destructive: false,
    );
    if (!ok) return;
    await Clipboard.setData(ClipboardData(text: store.exportBackup()));
    if (context.mounted) {
      showMessage(context, 'Backup copied. Paste it into Control on the other phone.');
    }
  }

  Future<void> _restoreBackup(BuildContext context, ServerStore store) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!context.mounted) return;
    if (text.trim().isEmpty) {
      showMessage(context, 'Copy a Control backup first, then tap Restore.');
      return;
    }
    try {
      final (servers, _) = ServerStore.parseBackup(text);
      final ok = await confirm(
        context,
        title: 'Restore ${servers.length} server${servers.length == 1 ? '' : 's'}?',
        body: 'Servers from this backup that are already here are updated.',
        action: 'Restore',
        destructive: false,
      );
      if (!ok) return;
      final n = await store.importBackup(text);
      if (context.mounted) {
        showMessage(context, 'Restored $n server${n == 1 ? '' : 's'}');
      }
    } on FormatException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}

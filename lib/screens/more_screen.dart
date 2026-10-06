import 'package:flutter/material.dart';

import '../models/server.dart';
import 'activity_screen.dart';
import 'indexer_search_screen.dart';
import 'requests_screen.dart';
import 'servers_screen.dart';
import 'subtitles_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(ServiceKind.prowlarr.icon),
            title: const Text('Search indexers'),
            subtitle: const Text('Prowlarr'),
            onTap: () => open(const IndexerSearchScreen()),
          ),
          ListTile(
            leading: Icon(ServiceKind.overseerr.icon),
            title: const Text('Requests'),
            subtitle: const Text('Overseerr / Jellyseerr'),
            onTap: () => open(const RequestsScreen()),
          ),
          ListTile(
            leading: Icon(ServiceKind.emby.icon),
            title: const Text('Now playing'),
            subtitle: const Text('Plex (Tautulli), Emby, Jellyfin'),
            onTap: () => open(const ActivityScreen()),
          ),
          ListTile(
            leading: Icon(ServiceKind.bazarr.icon),
            title: const Text('Subtitles'),
            subtitle: const Text('Bazarr'),
            onTap: () => open(const SubtitlesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servers'),
            subtitle: const Text('Add, edit and test connections'),
            onTap: () => open(const ServersScreen()),
          ),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: 'Control',
            applicationVersion: '1.0.0',
            aboutBoxChildren: const [
              Text(
                'Control your usenet, torrent and media servers from your phone.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

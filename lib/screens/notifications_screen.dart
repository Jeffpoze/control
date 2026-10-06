import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../services/ntfy.dart';
import '../services/sabnzbd.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Sets up "download finished" notifications on anyone's own server: picks an
/// ntfy server and a private topic, adds an ntfy connection to Sonarr,
/// Radarr, Lidarr and SABnzbd, and subscribes the phone in the ntfy app.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late NotifySettings _settings;
  final Set<String> _selected = {};
  final Map<String, Object?> _results = {};
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<ServerStore>();
    _settings = store.notify ?? NotifySettings(topic: randomTopic());
    _done = store.notify != null;
    _selected.addAll(store.ofKinds(ServiceKind.notifiers).map((s) => s.id));
  }

  ServerConfig _ntfy(ServerStore store) =>
      (_settings.serverId == null ? null : store.byId(_settings.serverId!)) ??
      publicNtfy;

  NtfyTarget _target(ServerStore store) =>
      NtfyTarget.of(_ntfy(store), _settings.topic);

  void _events(NotifyEvents e) =>
      setState(() => _settings = _settings.copyWith(events: e));

  Future<void> _setUp() async {
    final store = context.read<ServerStore>();
    final target = _target(store);
    setState(() {
      _busy = true;
      _results.clear();
    });
    await store.saveNotify(_settings);
    for (final server in store.ofKinds(ServiceKind.notifiers)) {
      if (!_selected.contains(server.id)) continue;
      try {
        final client = store.client(server);
        if (client is ArrClient) {
          await client.connectNtfy(target, _settings.events);
        } else if (client is SabnzbdClient) {
          await client.connectNtfy(target, _settings.events);
        }
        _results[server.id] = null;
      } catch (e) {
        _results[server.id] = e;
      }
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
    });
    final failed = _results.values.whereType<Object>().length;
    showMessage(
      context,
      failed == 0
          ? 'Notifications are set up. Now subscribe on this phone.'
          : '$failed app${failed == 1 ? '' : 's'} couldn\'t be set up.',
    );
  }

  Future<void> _test() async {
    final store = context.read<ServerStore>();
    final ntfy = _ntfy(store);
    final client = ntfy.id == publicNtfy.id
        ? NtfyClient(ntfy)
        : store.client<NtfyClient>(ntfy);
    await runAction(
      context,
      () => client.publish(
        _settings.topic,
        'Notifications from your media server will show up here.',
        title: 'Control is connected',
      ),
      done: 'Test sent. It should arrive in a few seconds.',
    );
    if (ntfy.id == publicNtfy.id) client.close();
  }

  Future<void> _openInNtfy() async {
    final target = _target(context.read<ServerStore>());
    var opened = false;
    try {
      opened = await launchUrl(
        target.appUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened) {
      try {
        opened = await launchUrl(
          target.webUrl,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
    if (!opened && mounted) {
      showMessage(context, 'Couldn\'t open ntfy. Copy the topic instead.');
    }
  }

  Future<void> _copy() async {
    final target = _target(context.read<ServerStore>());
    await Clipboard.setData(ClipboardData(text: target.webUrl.toString()));
    if (mounted) showMessage(context, 'Copied ${target.webUrl}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<ServerStore>();
    final ntfyServers = store.ofKinds({ServiceKind.ntfy});
    final notifiers = store.ofKinds(ServiceKind.notifiers);
    final hasSab = notifiers.any((s) => s.kind == ServiceKind.sabnzbd);
    final events = _settings.events;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Get a notification when something is downloaded, grabbed or '
              'goes wrong. Control adds the connection to your own apps, and '
              'the free ntfy app delivers it to this phone.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SectionHeader('Send through'),
          RadioGroup<String?>(
            groupValue: _settings.serverId,
            onChanged: (id) => setState(
              () => _settings = _settings.copyWith(
                serverId: id,
                publicServer: id == null,
              ),
            ),
            child: Column(
              children: [
                const RadioListTile<String?>(
                  value: null,
                  title: Text('ntfy.sh'),
                  subtitle: Text('Free public server, nothing to install'),
                ),
                for (final s in ntfyServers)
                  RadioListTile<String?>(
                    value: s.id,
                    title: Text(s.name),
                    subtitle: Text(
                      [
                        s.localUrl,
                        s.remoteUrl,
                      ].where((u) => u.isNotEmpty).join(' · '),
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Use your own ntfy server'),
            subtitle: const Text('Add it under Servers, then pick it here'),
            onTap: () => addServer(context, group: ServiceGroup.other),
          ),
          const SectionHeader('Your topic'),
          ListTile(
            title: SelectableText(
              _settings.topic,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            subtitle: const Text(
              'Anyone who knows it can read your notifications. Keep it private.',
            ),
            trailing: IconButton(
              tooltip: 'New topic',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(
                () => _settings = _settings.copyWith(topic: randomTopic()),
              ),
            ),
          ),
          const SectionHeader('Notify me when'),
          SwitchListTile(
            title: const Text('Something is downloaded'),
            subtitle: const Text(
              'Imported or upgraded by Sonarr, Radarr or Lidarr',
            ),
            value: events.imports,
            onChanged: (v) => _events(
              NotifyEvents(
                imports: v,
                grabs: events.grabs,
                problems: events.problems,
                sabComplete: events.sabComplete,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Something is grabbed'),
            subtitle: const Text('Sent to a download client'),
            value: events.grabs,
            onChanged: (v) => _events(
              NotifyEvents(
                imports: events.imports,
                grabs: v,
                problems: events.problems,
                sabComplete: events.sabComplete,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Something goes wrong'),
            subtitle: const Text(
              'Failed downloads or imports, health issues, a full disk',
            ),
            value: events.problems,
            onChanged: (v) => _events(
              NotifyEvents(
                imports: events.imports,
                grabs: events.grabs,
                problems: v,
                sabComplete: events.sabComplete,
              ),
            ),
          ),
          if (hasSab)
            SwitchListTile(
              title: const Text('SABnzbd finishes any download'),
              subtitle: const Text(
                'Also covers downloads Sonarr and Radarr don\'t manage',
              ),
              value: events.sabComplete,
              onChanged: (v) => _events(
                NotifyEvents(
                  imports: events.imports,
                  grabs: events.grabs,
                  problems: events.problems,
                  sabComplete: v,
                ),
              ),
            ),
          const SectionHeader('Set up in'),
          if (notifiers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Add Sonarr, Radarr, Lidarr or SABnzbd first.',
                style: muted,
              ),
            ),
          for (final s in notifiers)
            CheckboxListTile(
              value: _selected.contains(s.id),
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => v == true
                          ? _selected.add(s.id)
                          : _selected.remove(s.id),
                    ),
              secondary: Icon(s.kind.icon),
              title: Text(s.name),
              subtitle: !_results.containsKey(s.id)
                  ? null
                  : _results[s.id] == null
                  ? const Text(
                      'Connected',
                      style: TextStyle(color: Colors.green),
                    )
                  : Text(
                      errorText(_results[s.id]!),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              onPressed: _busy || _selected.isEmpty ? null : _setUp,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(
                _done ? 'Update notifications' : 'Set up notifications',
              ),
            ),
          ),
          const SectionHeader('On this phone'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '1. Install the free ntfy app from the App Store or Google Play.\n'
              '2. Subscribe to your topic with the button below. If the app '
              'doesn\'t open, copy the link and add it in ntfy with the + '
              'button.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openInNtfy,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in ntfy'),
                ),
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy link'),
                ),
                OutlinedButton.icon(
                  onPressed: _done ? _test : null,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send a test'),
                ),
              ],
            ),
          ),
          if (_settings.serverId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'With your own ntfy server, give it an away address (or use a '
                'VPN like Tailscale) so notifications reach you outside home.',
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}

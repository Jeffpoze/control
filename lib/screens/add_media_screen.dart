import 'package:flutter/material.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'media_screen.dart';

class AddMediaScreen extends StatefulWidget {
  const AddMediaScreen({super.key, required this.client});
  final ArrClient client;

  @override
  State<AddMediaScreen> createState() => _AddMediaScreenState();
}

class _AddMediaScreenState extends State<AddMediaScreen> {
  final _query = TextEditingController();
  List<MediaItem>? _results;
  Object? _error;
  bool _searching = false;

  ArrClient get client => widget.client;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await client.lookup(q);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(MediaItem result) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(client: client, result: result),
    );
    if (added == true && mounted) {
      showMessage(context, 'Added ${result.title}');
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noun = client.itemNoun;
    return Scaffold(
      appBar: AppBar(title: Text('Add $noun')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: switch (client.kind) {
                  ServiceKind.sonarr => 'Series name or tvdb:12345',
                  ServiceKind.radarr => 'Movie name or tmdb:12345',
                  _ => 'Artist name',
                },
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
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _search)
                : _results == null
                ? const SizedBox()
                : _results!.isEmpty
                ? const MessageView(icon: Icons.search_off, title: 'No matches')
                : ListView.builder(
                    itemCount: _results!.length,
                    itemBuilder: (_, i) {
                      final r = _results![i];
                      return MediaListTile(
                        item: r,
                        kind: client.kind,
                        onTap: r.inLibrary ? null : () => _add(r),
                        trailing: r.inLibrary
                            ? const StatusChip(
                                'In library',
                                color: Colors.green,
                              )
                            : const Icon(Icons.add_circle_outline),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.client, required this.result});
  final ArrClient client;
  final MediaItem result;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  List<Profile>? _quality;
  List<Profile> _language = const [];
  List<Profile> _metadata = const [];
  List<RootFolder>? _roots;
  Object? _error;

  int? _qualityId;
  int? _languageId;
  int? _metadataId;
  String? _root;
  String _monitor = 'all';
  String _availability = 'released';
  bool _searchNow = true;
  bool _adding = false;

  ArrClient get client => widget.client;

  @override
  void initState() {
    super.initState();
    _monitor = client.kind == ServiceKind.radarr ? 'movieOnly' : 'all';
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        client.qualityProfiles(),
        client.rootFolders(),
        if (client.kind == ServiceKind.sonarr) client.languageProfiles(),
        if (client.kind == ServiceKind.lidarr) client.metadataProfiles(),
      ]);
      if (!mounted) return;
      setState(() {
        _quality = results[0] as List<Profile>;
        _roots = results[1] as List<RootFolder>;
        if (client.kind == ServiceKind.sonarr) {
          _language = results[2] as List<Profile>;
        }
        if (client.kind == ServiceKind.lidarr) {
          _metadata = results[2] as List<Profile>;
        }
        _qualityId = _quality!.firstOrNull?.id;
        _root = _roots!.firstOrNull?.path;
        _languageId = _language.firstOrNull?.id;
        _metadataId = _metadata.firstOrNull?.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _submit() async {
    if (_qualityId == null || _root == null) return;
    setState(() => _adding = true);
    final ok = await runAction(context, () async {
      await client.add(
        client.addBody(
          widget.result,
          qualityProfileId: _qualityId!,
          rootFolderPath: _root!,
          languageProfileId: _languageId,
          metadataProfileId: _metadataId,
          search: _searchNow,
          monitor: _monitor,
          minimumAvailability: _availability,
        ),
      );
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final theme = Theme.of(context);
    const gap = SizedBox(height: 12);
    final monitorOptions = switch (client.kind) {
      ServiceKind.sonarr => const {
        'all': 'All episodes',
        'future': 'Future episodes',
        'missing': 'Missing episodes',
        'existing': 'Existing episodes',
        'firstSeason': 'First season',
        'latestSeason': 'Latest season',
        'pilot': 'Pilot only',
        'none': 'None',
      },
      ServiceKind.radarr => const {
        'movieOnly': 'Monitor',
        'none': 'Don\'t monitor',
      },
      _ => const {
        'all': 'All albums',
        'future': 'Future albums',
        'missing': 'Missing albums',
        'latest': 'Latest album',
        'first': 'First album',
        'none': 'None',
      },
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(
                    url: r.posterUrl,
                    width: 70,
                    height: 105,
                    icon: client.kind.icon,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: theme.textTheme.titleMedium),
                        if (r.year != null) Text('${r.year}'),
                        const SizedBox(height: 4),
                        Text(
                          r.overview,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  errorText(_error!),
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (_quality == null)
                const Center(child: CircularProgressIndicator())
              else if (_roots!.isEmpty)
                Text(
                  '${client.kind.label} has no root folder set up yet. '
                  'Add one in its Settings → Media Management first.',
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _root,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Root folder'),
                  items: [
                    for (final f in _roots!)
                      DropdownMenuItem(
                        value: f.path,
                        child: Text(
                          '${f.path}  (${formatBytes(f.freeSpace)} free)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _root = v),
                ),
                gap,
                DropdownButtonFormField<int>(
                  initialValue: _qualityId,
                  decoration: const InputDecoration(
                    labelText: 'Quality profile',
                  ),
                  items: [
                    for (final p in _quality!)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _qualityId = v),
                ),
                if (_language.isNotEmpty) ...[
                  gap,
                  DropdownButtonFormField<int>(
                    initialValue: _languageId,
                    decoration: const InputDecoration(
                      labelText: 'Language profile',
                    ),
                    items: [
                      for (final p in _language)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _languageId = v),
                  ),
                ],
                if (_metadata.isNotEmpty) ...[
                  gap,
                  DropdownButtonFormField<int>(
                    initialValue: _metadataId,
                    decoration: const InputDecoration(
                      labelText: 'Metadata profile',
                    ),
                    items: [
                      for (final p in _metadata)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _metadataId = v),
                  ),
                ],
                gap,
                DropdownButtonFormField<String>(
                  initialValue: _monitor,
                  decoration: const InputDecoration(labelText: 'Monitor'),
                  items: [
                    for (final e in monitorOptions.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _monitor = v ?? _monitor),
                ),
                if (client.kind == ServiceKind.radarr) ...[
                  gap,
                  DropdownButtonFormField<String>(
                    initialValue: _availability,
                    decoration: const InputDecoration(
                      labelText: 'Minimum availability',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'announced',
                        child: Text('Announced'),
                      ),
                      DropdownMenuItem(
                        value: 'inCinemas',
                        child: Text('In cinemas'),
                      ),
                      DropdownMenuItem(
                        value: 'released',
                        child: Text('Released'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _availability = v ?? _availability),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start searching now'),
                  value: _searchNow,
                  onChanged: (v) => setState(() => _searchNow = v),
                ),
                FilledButton(
                  onPressed: _adding ? null : _submit,
                  child: Text(_adding ? 'Adding…' : 'Add ${r.title}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

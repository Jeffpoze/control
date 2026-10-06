import 'package:flutter/material.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Change a series, movie or artist after adding it: monitoring, quality
/// profile, folder (moving the files), language or metadata profile, series
/// type, season folders and minimum availability. Pops the updated item.
class MediaEditScreen extends StatefulWidget {
  const MediaEditScreen({super.key, required this.client, required this.item});
  final ArrClient client;
  final MediaItem item;

  @override
  State<MediaEditScreen> createState() => _MediaEditScreenState();
}

class _MediaEditScreenState extends State<MediaEditScreen> {
  late final MediaEdit _edit = MediaEdit.of(widget.item);
  List<Profile>? _quality;
  List<Profile> _language = const [];
  List<Profile> _metadata = const [];
  List<RootFolder> _roots = const [];
  Object? _error;
  bool _saving = false;

  ArrClient get client => widget.client;
  ServiceKind get kind => client.kind;
  String get _originalRoot => MediaEdit.of(widget.item).rootFolderPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final quality = await client.qualityProfiles();
      final roots = await client.rootFolders();
      final language = kind == ServiceKind.sonarr && _edit.languageProfileId != null
          ? await client.languageProfiles()
          : const <Profile>[];
      final metadata = kind == ServiceKind.lidarr
          ? await client.metadataProfiles()
          : const <Profile>[];
      if (!mounted) return;
      setState(() {
        _quality = quality;
        _roots = roots;
        _language = language;
        _metadata = metadata;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await client.update(widget.item, _edit);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = _quality;
    final rootChanged = _edit.rootFolderPath != _originalRoot;
    // The current folder may not be a configured root folder any more.
    final rootPaths = {
      _originalRoot,
      for (final r in _roots) MediaEdit.trimSlash(r.path),
    }.where((p) => p.isNotEmpty).toList();
    final freeSpace = {
      for (final r in _roots) MediaEdit.trimSlash(r.path): r.freeSpace,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.item.title}'),
        actions: [
          TextButton(
            onPressed: quality == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : quality == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Monitored'),
                  subtitle: Text(
                    kind == ServiceKind.radarr
                        ? 'Download it when it becomes available'
                        : 'Download new and missing releases',
                  ),
                  value: _edit.monitored,
                  onChanged: (v) => setState(() => _edit.monitored = v),
                ),
                const SizedBox(height: 12),
                _dropdown<int>(
                  label: 'Quality profile',
                  value: _edit.qualityProfileId,
                  items: {for (final p in quality) p.id: p.name},
                  onChanged: (v) => _edit.qualityProfileId = v,
                ),
                if (_language.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _dropdown<int>(
                    label: 'Language profile',
                    value: _edit.languageProfileId!,
                    items: {for (final p in _language) p.id: p.name},
                    onChanged: (v) => _edit.languageProfileId = v,
                  ),
                ],
                if (_metadata.isNotEmpty && _edit.metadataProfileId != null) ...[
                  const SizedBox(height: 16),
                  _dropdown<int>(
                    label: 'Metadata profile',
                    value: _edit.metadataProfileId!,
                    items: {for (final p in _metadata) p.id: p.name},
                    onChanged: (v) => _edit.metadataProfileId = v,
                  ),
                ],
                if (_edit.minimumAvailability != null) ...[
                  const SizedBox(height: 16),
                  _dropdown<String>(
                    label: 'Minimum availability',
                    value: _edit.minimumAvailability!,
                    items: const {
                      'announced': 'Announced',
                      'inCinemas': 'In cinemas',
                      'released': 'Released',
                    },
                    onChanged: (v) => _edit.minimumAvailability = v,
                  ),
                ],
                if (_edit.seriesType != null) ...[
                  const SizedBox(height: 16),
                  _dropdown<String>(
                    label: 'Series type',
                    value: _edit.seriesType!,
                    items: const {
                      'standard': 'Standard',
                      'daily': 'Daily',
                      'anime': 'Anime',
                    },
                    onChanged: (v) => _edit.seriesType = v,
                  ),
                ],
                if (_edit.seasonFolder != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Season folders'),
                    value: _edit.seasonFolder!,
                    onChanged: (v) => setState(() => _edit.seasonFolder = v),
                  ),
                const SizedBox(height: 16),
                _dropdown<String>(
                  label: 'Folder',
                  value: _edit.rootFolderPath,
                  items: {
                    for (final p in rootPaths)
                      p: freeSpace[p] == null
                          ? p
                          : '$p  (${formatBytes(freeSpace[p]!)} free)',
                  },
                  onChanged: (v) => setState(() => _edit.rootFolderPath = v),
                ),
                const SizedBox(height: 4),
                Text(
                  'Now in ${widget.item.raw['path'] ?? _originalRoot}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (rootChanged)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Move the files too'),
                    subtitle: const Text(
                      'Otherwise only the new location is saved',
                    ),
                    value: _edit.moveFiles,
                    onChanged: (v) => setState(() => _edit.moveFiles = v),
                  ),
              ],
            ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    final entries = {...items};
    // Keep a value the server knows but the list doesn't (deleted profile).
    entries.putIfAbsent(value, () => '$value');
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in entries.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) setState(() => onChanged(v));
      },
    );
  }
}

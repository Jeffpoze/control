import 'package:flutter/material.dart';

import '../services/arr.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// What Sonarr/Radarr/Lidarr has sent to download clients and is tracking.
class ArrQueueScreen extends StatefulWidget {
  const ArrQueueScreen({super.key, required this.client});
  final ArrClient client;

  @override
  State<ArrQueueScreen> createState() => _ArrQueueScreenState();
}

class _ArrQueueScreenState extends State<ArrQueueScreen> {
  List<ArrQueueItem>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.client.queue();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _remove(ArrQueueItem item) async {
    var blocklist = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Remove from queue?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: blocklist,
                onChanged: (v) => setLocal(() => blocklist = v ?? false),
                title: const Text('Blocklist this release'),
                subtitle: const Text('So it isn\'t grabbed again'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (await runAction(
      context,
      () => widget.client.removeFromQueue(item, blocklist: blocklist),
      done: 'Removed',
    )) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.client.server.name} queue')),
      body: _error != null && _items == null
          ? ErrorView(error: _error!, onRetry: _load)
          : _items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items!.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        MessageView(
                          icon: Icons.inbox_outlined,
                          title: 'Queue is empty',
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _items!.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final q = _items![i];
                        return ListTile(
                          onLongPress: () => _remove(q),
                          title: Text(
                            q.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: q.progress),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  q.trackedState.isNotEmpty
                                      ? q.trackedState
                                      : q.status,
                                  formatBytes(q.sizeBytes),
                                  q.downloadClient,
                                ].where((s) => s.isNotEmpty).join(' · '),
                              ),
                              for (final m in q.messages)
                                Text(
                                  m,
                                  style: TextStyle(
                                    color: q.hasWarning
                                        ? Colors.orange
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(q),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

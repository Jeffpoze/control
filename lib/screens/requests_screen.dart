import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/overseerr.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Overseerr / Jellyseerr: approve or decline requests, and request new
/// movies and shows.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  String? _serverId;
  String _filter = 'pending';
  List<MediaRequest>? _requests;
  Object? _error;

  ServerConfig? _server(ServerStore store) {
    final servers = store.ofKinds({ServiceKind.overseerr});
    return servers.where((s) => s.id == _serverId).firstOrNull ??
        servers.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<ServerStore>();
    final server = _server(store);
    if (server == null) return;
    setState(() => _error = null);
    try {
      final r = await store
          .client<OverseerrClient>(server)
          .requests(filter: _filter);
      if (mounted) setState(() => _requests = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final server = _server(store);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Requests')),
        body: NoServersView(
          what: 'Overseerr or Jellyseerr',
          onAdd: () => addServer(context, group: ServiceGroup.requests),
        ),
      );
    }
    final client = store.client<OverseerrClient>(server);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        actions: [
          IconButton(
            tooltip: 'Request something',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DiscoverScreen(client: client),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ServerPicker(
            servers: store.ofKinds({ServiceKind.overseerr}),
            selectedId: server.id,
            onSelected: (s) {
              setState(() {
                _serverId = s.id;
                _requests = null;
              });
              _load();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'processing', label: Text('Processing')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_filter},
              onSelectionChanged: (v) {
                setState(() {
                  _filter = v.first;
                  _requests = null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : _requests == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _requests!.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              MessageView(
                                icon: Icons.inbox_outlined,
                                title: 'No requests',
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _requests!.length,
                            itemBuilder: (_, i) => _RequestTile(
                              request: _requests![i],
                              onApprove: () async {
                                if (await runAction(
                                  context,
                                  () => client.approve(_requests![i]),
                                  done: 'Approved',
                                )) {
                                  _load();
                                }
                              },
                              onDecline: () async {
                                if (await runAction(
                                  context,
                                  () => client.decline(_requests![i]),
                                  done: 'Declined',
                                )) {
                                  _load();
                                }
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onDecline,
  });
  final MediaRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Poster(
            url: r.posterUrl,
            width: 54,
            height: 81,
            icon: r.isTv ? Icons.tv : Icons.movie_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.title}${r.year != null ? ' (${r.year})' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    r.isTv ? 'Series' : 'Movie',
                    if (r.requestedBy.isNotEmpty) 'by ${r.requestedBy}',
                    if (r.createdAt != null) formatAgo(r.createdAt!),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                if (r.isPending)
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: onApprove,
                        child: const Text('Approve'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onDecline,
                        child: const Text('Decline'),
                      ),
                    ],
                  )
                else
                  StatusChip(
                    r.statusLabel,
                    color: r.status == 3
                        ? theme.colorScheme.error
                        : r.statusLabel == 'Available'
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverScreen extends StatefulWidget {
  const _DiscoverScreen({required this.client});
  final OverseerrClient client;

  @override
  State<_DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<_DiscoverScreen> {
  final _query = TextEditingController();
  List<DiscoverResult>? _results;
  Object? _error;
  final Set<int> _requested = {};

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    try {
      final r = await widget.client.search(q);
      if (mounted) {
        setState(() {
          _results = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Request')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Movie or show',
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(error: _error!, onRetry: _search)
              : ListView(
                  children: [
                    for (final r in _results ?? const <DiscoverResult>[])
                      ListTile(
                        leading: Poster(
                          url: r.posterUrl,
                          width: 40,
                          height: 60,
                        ),
                        title: Text(
                          '${r.title}${r.year != null ? ' (${r.year})' : ''}',
                        ),
                        subtitle: Text(
                          r.overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _requested.contains(r.tmdbId)
                            ? const StatusChip('Requested', color: Colors.green)
                            : r.canRequest
                            ? IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () async {
                                  if (await runAction(
                                    context,
                                    () => widget.client.submitRequest(r),
                                    done: 'Requested ${r.title}',
                                  )) {
                                    setState(() => _requested.add(r.tmdbId));
                                  }
                                },
                              )
                            : StatusChip(r.availabilityLabel),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

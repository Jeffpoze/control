import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/arr.dart';
import '../state/server_store.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'servers_screen.dart';

/// Loads upcoming items from every Sonarr, Radarr and Lidarr, sorted by time.
/// Servers that fail are skipped and reported in [errors].
Future<(List<CalendarEntry>, List<String>)> loadCalendar(
  ServerStore store,
  DateTime start,
  DateTime end,
) async {
  final servers = store.ofGroup(ServiceGroup.media);
  final errors = <String>[];
  final lists = await Future.wait(
    servers.map((s) async {
      try {
        return await store.client<ArrClient>(s).calendar(start, end);
      } catch (e) {
        errors.add(errorText(e));
        return <CalendarEntry>[];
      }
    }),
  );
  final all = lists.expand((l) => l).toList()
    ..sort((a, b) => a.when.compareTo(b.when));
  return (all, errors);
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<CalendarEntry>? _entries;
  List<String> _errors = const [];
  int _serverCount = -1;
  int _days = 14;

  Future<void> _load() async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final (entries, errors) = await loadCalendar(
      context.read<ServerStore>(),
      start,
      start.add(Duration(days: _days + 1)),
    );
    if (mounted) {
      setState(() {
        _entries = entries;
        _errors = errors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ServerStore>();
    final count = store.ofGroup(ServiceGroup.media).length;
    if (count != _serverCount) {
      _serverCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    if (count == 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: NoServersView(
          what: 'Sonarr, Radarr or Lidarr',
          onAdd: () => addServer(context, group: ServiceGroup.media),
        ),
      );
    }

    final entries = _entries;
    final groups = <DateTime, List<CalendarEntry>>{};
    for (final e in entries ?? const <CalendarEntry>[]) {
      groups
          .putIfAbsent(
            DateTime(e.when.year, e.when.month, e.when.day),
            () => [],
          )
          .add(e);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _days,
            icon: const Icon(Icons.date_range),
            onSelected: (d) {
              setState(() => _days = d);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Next week')),
              PopupMenuItem(value: 14, child: Text('Next 2 weeks')),
              PopupMenuItem(value: 30, child: Text('Next month')),
            ],
          ),
        ],
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  for (final err in _errors)
                    MaterialBanner(
                      content: Text(err),
                      actions: const [SizedBox()],
                    ),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: MessageView(
                        icon: Icons.event_available,
                        title: 'Nothing coming up',
                      ),
                    ),
                  for (final day in groups.keys) ...[
                    SectionHeader(formatDay(day)),
                    for (final e in groups[day]!) CalendarTile(entry: e),
                  ],
                ],
              ),
            ),
    );
  }
}

class CalendarTile extends StatelessWidget {
  const CalendarTile({super.key, required this.entry});
  final CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTime = entry.kind == ServiceKind.sonarr;
    return ListTile(
      leading: Poster(
        url: entry.posterUrl,
        width: 36,
        height: 54,
        icon: entry.kind.icon,
      ),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasTime)
            Text(
              DateFormat.jm().format(entry.when),
              style: theme.textTheme.labelMedium,
            ),
          if (entry.hasFile)
            const Icon(Icons.check_circle, color: Colors.green, size: 18)
          else if (entry.when.isBefore(DateTime.now()))
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
        ],
      ),
    );
  }
}

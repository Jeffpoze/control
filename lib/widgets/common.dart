import 'package:flutter/material.dart';

import '../models/server.dart';
import '../services/service_client.dart';

/// Shows [error] in a friendly way, with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.wifi_off_rounded,
    title: 'Couldn\'t load',
    body: errorText(error),
    action: onRetry == null
        ? null
        : FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
  );
}

String errorText(Object error) =>
    error is ApiException ? error.message : 'Something went wrong: $error';

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Shown on a tab when no server of the right kind has been added.
class NoServersView extends StatelessWidget {
  const NoServersView({super.key, required this.what, required this.onAdd});
  final String what;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.dns_outlined,
    title: 'No $what yet',
    body: 'Add one in More → Servers.',
    action: FilledButton(onPressed: onAdd, child: const Text('Add a server')),
  );
}

/// Chips to switch between servers of the same group.
class ServerPicker extends StatelessWidget {
  const ServerPicker({
    super.key,
    required this.servers,
    required this.selectedId,
    required this.onSelected,
    this.labelOf,
  });

  final List<ServerConfig> servers;
  final String? selectedId;
  final ValueChanged<ServerConfig> onSelected;

  /// The chip text; the server name by default.
  final String Function(ServerConfig)? labelOf;

  @override
  Widget build(BuildContext context) {
    if (servers.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final s in servers)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(s.kind.icon, size: 18),
                label: Text(labelOf?.call(s) ?? s.name),
                selected: s.id == selectedId,
                showCheckmark: false,
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}

/// A poster image with a placeholder while loading or when missing.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    this.url,
    this.width,
    this.height,
    this.icon = Icons.movie_outlined,
    this.headers,
  });
  final String? url;
  final double? width;
  final double? height;
  final IconData icon;

  /// For images that need a session cookie (Comicarr's cached covers).
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, color: Theme.of(context).colorScheme.outline),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              headers: headers,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) =>
                  frame == null && !sync ? placeholder : child,
            ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [action]; shows [done] when it works and the error when it doesn't.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  try {
    await action();
    if (context.mounted && done != null) showMessage(context, done);
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  String action = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a line of text (a link, a search…).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String action = 'Add',
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}

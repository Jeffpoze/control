import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/clients.dart';
import '../state/server_store.dart';
import '../widgets/common.dart';

class ServerEditScreen extends StatefulWidget {
  const ServerEditScreen({super.key, required this.kind, this.existing});
  final ServiceKind kind;
  final ServerConfig? existing;

  @override
  State<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends State<ServerEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.kind.label,
  );
  late final _local = TextEditingController(
    text: widget.existing?.localUrl ?? '',
  );
  late final _remote = TextEditingController(
    text: widget.existing?.remoteUrl ?? '',
  );
  late final _apiKey = TextEditingController(
    text: widget.existing?.apiKey ?? '',
  );
  late final _user = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final _pass = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  late final _proxyUser = TextEditingController(
    text: widget.existing?.proxyUser ?? '',
  );
  late final _proxyPass = TextEditingController(
    text: widget.existing?.proxyPassword ?? '',
  );
  late final _headers = TextEditingController(
    text: widget.existing?.customHeaders ?? '',
  );

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _showSecret = false;
  late bool _advanced = (widget.existing?.proxyUser ?? '').isNotEmpty;
  late bool _showHeaders = (widget.existing?.customHeaders ?? '')
      .trim()
      .isNotEmpty;

  ServiceKind get kind => widget.kind;

  ServerConfig _build() => ServerConfig(
    id: widget.existing?.id ?? ServerStore.newId(),
    kind: kind,
    name: _name.text.trim().isEmpty ? kind.label : _name.text.trim(),
    localUrl: _local.text.trim(),
    remoteUrl: _remote.text.trim(),
    apiKey: _apiKey.text.trim(),
    username: _user.text.trim(),
    password: _pass.text,
    proxyUser: _proxyUser.text.trim(),
    proxyPassword: _proxyPass.text,
    customHeaders: _headers.text.trim(),
  );

  String? _validateUrl(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null;
    try {
      final u = normalizeUrl(s);
      if (u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) {
        return 'Use an address like 192.168.1.10:${kind.defaultPort}';
      }
    } on FormatException {
      return 'That isn\'t a valid address';
    }
    return null;
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final server = _build();
    final results = <String>[];
    var ok = true;
    // Test each address on its own, so the user knows which one works.
    for (final (label, url) in [
      ('Home', server.localUrl),
      ('Away', server.remoteUrl),
    ]) {
      if (url.isEmpty) continue;
      final single = ServerConfig(
        id: server.id,
        kind: kind,
        name: server.name,
        localUrl: url,
        apiKey: server.apiKey,
        username: server.username,
        password: server.password,
        proxyUser: server.proxyUser,
        proxyPassword: server.proxyPassword,
        customHeaders: server.customHeaders,
      );
      final client = createClient(single);
      try {
        await client.test();
        results.add('$label address: connected');
      } catch (e) {
        ok = false;
        results.add('$label address: ${errorText(e)}');
      } finally {
        client.close();
      }
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = results.join('\n');
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await context.read<ServerStore>().save(_build());
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Remove ${widget.existing!.name}?',
      body: 'This only removes it from Control. Nothing changes on the server.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await context.read<ServerStore>().remove(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _local,
      _remote,
      _apiKey,
      _user,
      _pass,
      _proxyUser,
      _proxyPass,
      _headers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add ${kind.label}' : widget.existing!.name,
        ),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            gap,
            TextFormField(
              controller: _local,
              decoration: InputDecoration(
                labelText: 'Home address',
                hintText: '192.168.1.10:${kind.defaultPort}',
                helperText:
                    'Used on your home network. Include any URL base, like /${kind.name}.',
                helperMaxLines: 2,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) {
                if ((v ?? '').trim().isEmpty && _remote.text.trim().isEmpty) {
                  return 'Add at least one address';
                }
                return _validateUrl(v);
              },
            ),
            gap,
            TextFormField(
              controller: _remote,
              decoration: InputDecoration(
                labelText: 'Away address (optional)',
                hintText: 'https://${kind.name}.example.com',
                helperText: 'Used when the home address doesn\'t answer.',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: _validateUrl,
            ),
            gap,
            if (kind.auth == AuthStyle.apiKey)
              TextFormField(
                controller: _apiKey,
                obscureText: !_showSecret,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: kind.apiKeyLabel,
                  helperText: kind.apiKeyHint,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showSecret ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
                validator: (v) => (v ?? '').trim().isEmpty && !kind.apiKeyOptional
                    ? 'Enter the API key'
                    : null,
              )
            else ...[
              TextFormField(
                controller: _user,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: InputDecoration(
                  labelText: kind.usernameOptional
                      ? 'Username (if set)'
                      : 'Username',
                ),
              ),
              gap,
              TextFormField(
                controller: _pass,
                obscureText: !_showSecret,
                autocorrect: false,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showSecret ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reverse proxy login'),
              subtitle: const Text('Basic auth in front of the app'),
              value: _advanced,
              onChanged: (v) => setState(() => _advanced = v),
            ),
            if (_advanced) ...[
              TextFormField(
                controller: _proxyUser,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Proxy username'),
              ),
              gap,
              TextFormField(
                controller: _proxyPass,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Proxy password'),
              ),
              gap,
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Custom headers'),
              subtitle: const Text(
                'For Cloudflare Access, Authelia and other proxies',
              ),
              value: _showHeaders,
              onChanged: (v) => setState(() => _showHeaders = v),
            ),
            if (_showHeaders) ...[
              TextFormField(
                controller: _headers,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 2,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Headers',
                  hintText: 'CF-Access-Client-Id: abc.access\nCF-Access-Client-Secret: …',
                  helperText: 'One per line, as Name: value',
                ),
                validator: (v) {
                  for (final line in (v ?? '').split('\n')) {
                    if (line.trim().isEmpty) continue;
                    if (parseHeaderLines(line).isEmpty) {
                      return 'Can\'t read "${line.trim()}". Use Name: value';
                    }
                  }
                  return null;
                },
              ),
              gap,
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testOk ? Icons.check_circle : Icons.error_outline,
                        color: _testOk ? Colors.green : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_testResult!)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Keys, passwords and headers are stored in this phone\'s secure storage only.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove server'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

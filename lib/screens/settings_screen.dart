import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/podcast_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<PodcastStore>();
    _url = TextEditingController(text: store.scriptUrl);
    _token = TextEditingController(text: store.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  bool get _valid => _url.text.trim().isNotEmpty && _token.text.trim().isNotEmpty;

  Future<void> _test() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status =
          await context.read<PodcastStore>().testConnection(_url.text, _token.text);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Connected (script v${status.version}). '
              '${status.count} podcasts found in the sheet.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await context.read<PodcastStore>().saveSettings(_url.text, _token.text);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connect your Google Sheet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste the Apps Script web app URL (ends with /exec) and the TOKEN '
            'you set in Code.gs. See the README for setup steps.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Script URL',
              hintText: 'https://script.google.com/macros/s/.../exec',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: _obscure,
            // Keep the keyboard from capitalizing or "correcting" the token.
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _valid && !_busy ? _test : null,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _valid && !_busy ? _save : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

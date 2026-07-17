import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pill_button.dart';

/// Server connection settings (base URL + API token).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(serverSettingsProvider.notifier).save(
          baseUrl: _urlController.text,
          apiToken: _tokenController.text,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(serverSettingsProvider);
    final theme = Theme.of(context);

    // Populate the fields once from stored settings.
    if (!_initialized && settings.hasValue) {
      _urlController.text = settings.requireValue.baseUrl;
      _tokenController.text = settings.requireValue.apiToken;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Server connection'),
                const SizedBox(height: AppDimens.unit * 2),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.10:3000',
                  ),
                ),
                const SizedBox(height: AppDimens.gutter),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API token'),
                ),
                const SizedBox(height: AppDimens.gutter),
                PillButton(label: 'Save', icon: Icons.check, onPressed: _save),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gutter),
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('About'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'MangaVault — archival storage for your manga & manhwa '
                  'libraries, imported from Mihon-compatible backups.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

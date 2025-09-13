import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:anydrop/services/settings_store.dart';
import 'package:anydrop/pages/edit_profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final s = SettingsStore.instance;

  IconData _avatarIcon(int idx) {
    const icons = <IconData>[
      Icons.person,
      Icons.face_3,
      Icons.mood,
      Icons.emoji_emotions,
      Icons.face_retouching_natural,
      Icons.sentiment_satisfied_alt,
    ];
    return icons[idx % icons.length];
  }

  Future<void> _pickDownloadDir() async {
    final path = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Select download folder');
    if (path != null) {
      await s.setCustomDownloadDir(path);
      if (mounted) setState(() {});
    }
  }

  Future<void> _resetDownloadDir() async {
    await s.setCustomDownloadDir(null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [s.themeMode, s.downloadDirPath, s.displayName, s.avatarId]),
      builder: (context, _) {
        final dir =
            s.downloadDirPath.value ?? '/storage/emulated/0/Download/AnyDrop';

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile
              Text('Edit profile',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: s.avatarId,
                    builder: (_, idx, __) => CircleAvatar(
                      radius: 26,
                      child: Icon(_avatarIcon(idx), size: 26),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: s.displayName,
                      builder: (_, name, __) => Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit profile'),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EditProfilePage()),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Appearance
              Text('Appearance',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),

              ValueListenableBuilder<ThemeMode>(
                valueListenable: s.themeMode,
                builder: (_, mode, __) => Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text('Use device theme'),
                      subtitle:
                          const Text('Automatically match system light/dark'),
                      value: ThemeMode.system,
                      groupValue: mode,
                      onChanged: (m) => s.setThemeMode(m ?? ThemeMode.system),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('Light'),
                      subtitle: const Text('Always use light theme'),
                      value: ThemeMode.light,
                      groupValue: mode,
                      onChanged: (m) => s.setThemeMode(m ?? ThemeMode.light),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('Dark'),
                      subtitle: const Text('Always use dark theme'),
                      value: ThemeMode.dark,
                      groupValue: mode,
                      onChanged: (m) => s.setThemeMode(m ?? ThemeMode.dark),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Downloads
              Text('Downloads',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Download folder'),
                subtitle: Text(
                  dir,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton(
                  onPressed: _pickDownloadDir,
                  child: const Text('Choose'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _resetDownloadDir,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset to default'),
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              // Notes
              Text(
                'Notes:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '• On some Android devices, folder pickers can be limited.\n'
                '• If choosing a folder fails, the app uses a safe default (Downloads/AnyDrop).\n'
                '• iOS saves to app Documents/AnyDrop (exposed via Files app).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

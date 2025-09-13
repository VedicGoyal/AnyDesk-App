import 'package:flutter/material.dart';
import 'package:anydrop/pages/history_page.dart';
import 'package:anydrop/pages/settings_page.dart';
import 'package:anydrop/pages/about_page.dart';
import 'package:anydrop/pages/edit_profile_page.dart';
import 'package:anydrop/services/cache_service.dart';
import 'package:anydrop/services/settings_store.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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

  @override
  Widget build(BuildContext context) {
    final s = SettingsStore.instance;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfilePage()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Row(
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: s.avatarId,
                      builder: (_, idx, __) => CircleAvatar(
                        radius: 28,
                        child: Icon(_avatarIcon(idx), size: 28),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: s.displayName,
                        builder: (_, name, __) => Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const Icon(Icons.edit, size: 18),
                  ],
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Licenses'),
              onTap: () {
                Navigator.pop(context);
                showLicensePage(
                  context: context,
                  applicationName: 'AnyDrop',
                  applicationVersion: '0.1.0',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('Clear cache'),
              onTap: () async {
                Navigator.pop(context);
                await CacheService.instance.clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

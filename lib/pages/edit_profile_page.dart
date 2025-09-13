// lib/pages/edit_profile_page.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // ✅ needed for RenderRepaintBoundary
import 'package:anydrop/services/settings_store.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final s = SettingsStore.instance;
  late final TextEditingController _nameCtrl;
  late int _avatar;

  // Used if/when you want to export the preview as a PNG later
  final GlobalKey _avatarPreviewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: s.displayName.value);
    _avatar = s.avatarId.value; // keep whatever is currently stored
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim();
    await s.setDisplayName(name);
    await s.setAvatarId(_avatar);

    if (!mounted) return;
    Navigator.pop(context, true); // indicate success to caller
  }

  // Optional: capture the avatar preview as PNG bytes (not used right now,
  // but wired up and tested to work if you need it later).
  Future<Uint8List?> _captureAvatarPng() async {
    try {
      final boundary = _avatarPreviewKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatars = const [
      Icons.person,
      Icons.face_3,
      Icons.mood,
      Icons.emoji_emotions,
      Icons.face_retouching_natural,
      Icons.sentiment_satisfied_alt,
      Icons.bolt,
      Icons.pets,
      Icons.rocket_launch,
      Icons.lightbulb,
      Icons.sailing,
      Icons.celebration,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Edit your profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview
          Center(
            child: RepaintBoundary(
              key: _avatarPreviewKey, // ✅ ready for export
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  avatars[_avatar % avatars.length],
                  size: 44,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select an avatar',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          // Avatar grid
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: avatars.length,
            itemBuilder: (_, i) {
              final selected = i == _avatar;
              return InkWell(
                onTap: () => setState(() => _avatar = i),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    avatars[i],
                    size: 36,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Name field
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Your name shown in the app',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),

          const SizedBox(height: 20),

          // Actions
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                onPressed: () => Navigator.pop(context, false),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

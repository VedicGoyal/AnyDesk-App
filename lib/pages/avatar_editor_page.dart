import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:anydrop/services/settings_store.dart';

import 'package:flutter/rendering.dart';

//import 'package:avatar_maker/avatar_maker.dart';

class AvatarEditorPage extends StatefulWidget {
  final bool fromOnboarding; // if true, pop with success
  const AvatarEditorPage({super.key, this.fromOnboarding = false});

  @override
  State<AvatarEditorPage> createState() => _AvatarEditorPageState();
}

class _AvatarEditorPageState extends State<AvatarEditorPage> {
  final s = SettingsStore.instance;
  late final TextEditingController _nameCtrl;

  // Where we render the avatar to PNG
  final _avatarKey = GlobalKey();

  // If your maker exposes a config string, keep it here.
  String? _makerConfig; // set this from the maker's onChanged / controller

  // A very simple local “design” fallback so this page compiles without the pkg
  Color _bg = Colors.teal.shade400;
  Color _fg = Colors.amber.shade200;
  IconData _icon = Icons.person;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: s.displayName.value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<String> _savePngFromRepaintBoundary() async {
    final boundary =
        _avatarKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'avatar_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim();
    await s.setDisplayName(name);

    // Render PNG from the widget tree
    String pngPath = await _savePngFromRepaintBoundary();

    // Persist PNG path (+ maker config if you have it)
    await s.setAvatarMakerResult(pngPath: pngPath, config: _makerConfig);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.fromOnboarding ? 'Choose avatar & name' : 'Edit profile';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: RepaintBoundary(
              key: _avatarKey,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: _bg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                // ── Replace this fallback with the real maker widget ─────────
                // AvatarMaker(
                //   initialConfig: s.avatarConfig.value,
                //   onChanged: (cfg) => _makerConfig = cfg,   // string/json
                // ),
                child: Icon(_icon, size: 96, color: _fg),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Simple controls for the fallback (remove when maker is live)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Icon'),
                onSelected: (_) {
                  setState(() {
                    _icon = (_icon == Icons.person)
                        ? Icons.face_6
                        : (_icon == Icons.face_6)
                            ? Icons.sentiment_satisfied_alt
                            : Icons.person;
                  });
                },
              ),
              FilterChip(
                label: const Text('Swap colors'),
                onSelected: (_) => setState(() {
                  final c = _bg;
                  _bg = _fg;
                  _fg = c;
                }),
              ),
            ],
          ),

          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Save'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

// lib/pages/apps_chooser_page.dart
import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';

class AppsChooserPage extends StatefulWidget {
  final List<Application> apps;
  const AppsChooserPage({super.key, required this.apps});

  @override
  State<AppsChooserPage> createState() => _AppsChooserPageState();
}

class _AppsChooserPageState extends State<AppsChooserPage> {
  final _selected = <String>{}; // package names
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.apps.where((a) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q);
    }).toList()
      ..sort(
          (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              final picked = widget.apps
                  .where((a) => _selected.contains(a.packageName))
                  .toList();
              Navigator.pop(context, picked);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final a = filtered[i];
          final selected = _selected.contains(a.packageName);
          return ListTile(
            leading: a is ApplicationWithIcon
                ? CircleAvatar(backgroundImage: MemoryImage(a.icon))
                : const CircleAvatar(child: Icon(Icons.android)),
            title: Text(a.appName),
            subtitle: Text(
              a.packageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Checkbox(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(a.packageName);
                  } else {
                    _selected.remove(a.packageName);
                  }
                });
              },
            ),
            onTap: () {
              setState(() {
                if (selected) {
                  _selected.remove(a.packageName);
                } else {
                  _selected.add(a.packageName);
                }
              });
            },
          );
        },
      ),
    );
  }
}

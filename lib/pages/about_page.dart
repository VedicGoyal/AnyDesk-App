import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _open(Uri uri, BuildContext context) async {
    final ok = await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('AnyDrop'),
            subtitle: Text('Fast local file sharing across devices.'),
          ),
          const SizedBox(height: 8),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: const Text('vedicgoyal@gmail.com'),
            onTap: () =>
                _open(Uri.parse('mailto:vedicgoyal@gmail.com'), context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub'),
            subtitle: const Text('github.com/VedicGoyal'),
            onTap: () =>
                _open(Uri.parse('https://github.com/VedicGoyal'), context),
          ),
          ListTile(
            leading: const Icon(Icons.business_center_outlined),
            title: const Text('LinkedIn'),
            subtitle: const Text('linkedin.com/in/vedic-goyal'),
            onTap: () => _open(
                Uri.parse('https://www.linkedin.com/in/vedic-goyal'), context),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Tip: AnyDrop works best when both devices are on the same Wi-Fi network or one device shares a hotspot.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

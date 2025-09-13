// lib/pages/onboarding_page.dart
import 'package:anydrop/pages/avatar_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:anydrop/services/settings_store.dart';
import 'package:anydrop/pages/edit_profile_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _page = PageController();
  int _index = 0;

  void _next() {
    if (_index < 2) {
      _page.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, false),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _Slide(
                    icon: Icons.rocket_launch,
                    title: 'Welcome to AnyDrop!',
                    body:
                        'Share files over Wi-Fi or mobile hotspot.\nNo internet needed.',
                  ),
                  _Slide(
                    icon: Icons.wifi,
                    title: 'Connect locally',
                    body:
                        'Make sure both devices are on the same Wi-Fi\nor one device shares a hotspot.',
                  ),
                  _Slide(
                    icon: Icons.palette_outlined,
                    title: 'Make it yours',
                    body:
                        'Pick an avatar and set your display name.\nYou can change it anytime in Settings.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            dots,
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  // Back / Maybe later
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        _index == 0 ? Icons.arrow_back : Icons.skip_next,
                      ),
                      label: Text(_index == 2 ? 'Maybe later' : 'Back'),
                      onPressed: () {
                        if (_index == 0) {
                          Navigator.pop(context, false);
                        } else if (_index == 2) {
                          // user skips personalization
                          Navigator.pop(
                              context, true); // mark as onboarded upstream
                        } else {
                          _page.previousPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Next / Choose avatar
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (_index < 2) {
                          _next();
                          return;
                        }
                        // open edit profile
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AvatarEditorPage(
                              fromOnboarding: true,
                            ),
                          ),
                        );
                        if (!mounted) return;
                        if (saved == true) {
                          // personalization done -> finish onboarding
                          await SettingsStore.instance.markOnboarded();
                          if (mounted) Navigator.pop(context, true);
                        } else {
                          // user backed out; stay on page
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Profile not saved. You can do it later in Settings.',
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        _index == 2 ? 'Choose avatar & name' : 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 88,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

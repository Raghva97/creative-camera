import 'package:flutter/material.dart';

import '../modes/shoot_mode.dart';
import '../modes/video_preset.dart';
import 'creative_camera_screen.dart';
import 'live_setup_screen.dart';
import 'video_screen.dart';

/// Start screen: pick a way to shoot.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Creative Camera')),
          _section(
            context,
            'Creative photo',
            'Light, night and landscape tricks',
          ),
          _grid([
            for (final m in photoModes)
              _ModeTile(
                name: m.name,
                tagline: m.tagline,
                icon: m.icon,
                color: m.color,
                onTap: () => _open(context, CreativeCameraScreen(mode: m)),
              ),
          ]),
          _section(
            context,
            'Video for YouTube',
            'Presets tuned for each kind of video',
          ),
          _grid([
            for (final p in videoPresets)
              _ModeTile(
                name: p.name,
                tagline: p.tagline,
                icon: p.icon,
                color: p.color,
                onTap: () => _open(context, VideoScreen(preset: p)),
              ),
          ]),
          _section(context, 'Go live', 'Stream straight to YouTube over RTMP'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _ModeTile(
                name: 'YouTube Live',
                tagline: 'Also works with Facebook, Twitch or any RTMP server',
                icon: Icons.wifi_tethering,
                color: Colors.red,
                wide: true,
                onTap: () => _open(context, const LiveSetupScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  Widget _section(BuildContext context, String title, String subtitle) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );

  Widget _grid(List<Widget> children) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverGrid.extent(
      maxCrossAxisExtent: 220,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: children,
    ),
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    required this.onTap,
    this.wide = false,
  });

  final String name;
  final String tagline;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: color,
                child: Icon(icon, color: Colors.white),
              ),
              SizedBox(height: wide ? 12 : 0),
              if (!wide) const Spacer(),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_screen.dart';

/// Quality ladder for live streaming, following YouTube's recommended
/// encoder settings for H.264 at 30 fps.
enum LiveQuality {
  p480('480p (weak network)', 854, 480, 1200000),
  p720('720p (recommended)', 1280, 720, 3000000),
  p1080('1080p (fast Wi-Fi / 5G)', 1920, 1080, 5000000);

  const LiveQuality(this.label, this.width, this.height, this.bitrate);
  final String label;
  final int width;
  final int height;
  final int bitrate;
}

class LiveConfig {
  LiveConfig({
    required this.server,
    required this.streamKey,
    required this.quality,
    required this.portrait,
    required this.overlayText,
  });

  final String server;
  final String streamKey;
  final LiveQuality quality;
  final bool portrait;
  final String overlayText;

  String get url {
    final s = server.endsWith('/')
        ? server.substring(0, server.length - 1)
        : server;
    return '$s/$streamKey';
  }
}

/// Collects the RTMP server and stream key before going live.
class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({super.key});

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen> {
  static const youtubeServer = 'rtmp://a.rtmp.youtube.com/live2';

  final _server = TextEditingController(text: youtubeServer);
  final _key = TextEditingController();
  final _overlay = TextEditingController();
  LiveQuality _quality = LiveQuality.p720;
  bool _portrait = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _server.text = p.getString('live.server') ?? youtubeServer;
      _key.text = p.getString('live.key') ?? '';
      _overlay.text = p.getString('live.overlay') ?? '';
      _quality = LiveQuality.values[p.getInt('live.quality') ?? 1];
      _portrait = p.getBool('live.portrait') ?? false;
    });
  }

  Future<void> _go() async {
    if (_key.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste your stream key from YouTube Studio.'),
        ),
      );
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('live.server', _server.text.trim());
    await p.setString('live.key', _key.text.trim());
    await p.setString('live.overlay', _overlay.text);
    await p.setInt('live.quality', _quality.index);
    await p.setBool('live.portrait', _portrait);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(
          config: LiveConfig(
            server: _server.text.trim(),
            streamKey: _key.text.trim(),
            quality: _quality,
            portrait: _portrait,
            overlayText: _overlay.text.trim(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _server.dispose();
    _key.dispose();
    _overlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Live')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'In YouTube Studio choose Create > Go live > Stream. Copy the '
                'stream key and paste it below. Your channel must have live '
                'streaming enabled (it can take 24 hours the first time). '
                'Works with any RTMP service: Facebook, Twitch, or your own server.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _server,
            decoration: const InputDecoration(
              labelText: 'RTMP server URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: 'Stream key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LiveQuality>(
            initialValue: _quality,
            decoration: const InputDecoration(
              labelText: 'Quality',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final q in LiveQuality.values)
                DropdownMenuItem(value: q, child: Text(q.label)),
            ],
            onChanged: (q) => setState(() => _quality = q ?? _quality),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Vertical (Shorts style)'),
            subtitle: const Text('Off for normal 16:9 landscape streams'),
            value: _portrait,
            onChanged: (v) => setState(() => _portrait = v),
          ),
          TextField(
            controller: _overlay,
            decoration: const InputDecoration(
              labelText: 'On-screen title (optional)',
              hintText: 'e.g. Sunday Biryani Live',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _go,
            icon: const Icon(Icons.videocam),
            label: const Text('Open live camera'),
          ),
        ],
      ),
    );
  }
}

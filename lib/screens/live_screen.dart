import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:haishin_kit/haishin_kit.dart';
// AVCaptureSessionPreset is not re-exported by the package.
// ignore: implementation_imports
import 'package:haishin_kit/src/stream_session/av_capture_session_preset.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../widgets/common.dart';
import 'live_setup_screen.dart';

/// Camera preview plus RTMP publishing through HaishinKit
/// (HaishinKit.kt on Android, HaishinKit.swift on iOS).
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.config});
  final LiveConfig config;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  LiveConfig get config => widget.config;

  MediaMixer? _mixer;
  StreamSession? _session;
  List<VideoSource> _sources = [];
  VideoSource? _current;
  bool _muted = false;
  String? _error;
  StreamSubscription<StreamSessionReadyState>? _stateSub;
  StreamSessionReadyState _state = StreamSessionReadyState.closed;
  DateTime? _liveSince;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
      config.portrait
          ? [DeviceOrientation.portraitUp]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stateSub?.cancel();
    _session?.close();
    _session?.dispose();
    _mixer?.stopRunning();
    _mixer?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      // On iOS the system asks for camera and microphone access the first
      // time HaishinKit opens them, so only Android needs an explicit ask.
      if (Platform.isAndroid) {
        final cam = await Permission.camera.request();
        final mic = await Permission.microphone.request();
        if (!cam.isGranted || !mic.isGranted) {
          setState(
            () => _error =
                'Camera and microphone permission are needed to go live.',
          );
          return;
        }
      }

      if (Platform.isIOS) {
        final audio = await AudioSession.instance;
        await audio.configure(
          AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.defaultToSpeaker,
          ),
        );
      }

      _sources = await HaishinKitPlatformInterface.instance.videoSources;
      _current =
          _sources
              .where((s) => s.position == CameraPosition.back)
              .firstOrNull ??
          _sources.firstOrNull;
      if (_current == null) {
        setState(() => _error = 'No camera found.');
        return;
      }

      final q = config.quality;
      final mixer = await MediaMixer.create();
      if (Platform.isIOS) {
        mixer.sessionPreset = q == LiveQuality.p1080
            ? AVCaptureSessionPreset.hd1920x1080
            : AVCaptureSessionPreset.hd1280x720;
      }
      mixer.frameRate = 30;
      await mixer.attachAudio(0, AudioSource());
      await mixer.attachVideo(0, _current);
      mixer.screen?.size = config.portrait
          ? ScreenObjectSize(width: q.height, height: q.width)
          : ScreenObjectSize(width: q.width, height: q.height);

      if (config.overlayText.isNotEmpty) {
        final text = TextScreenObject();
        text.value = config.overlayText;
        text.fontSize = q.height / 18;
        text.verticalAlignment = VerticalAlignment.bottom;
        text.horizontalAlignment = HorizontalAlignment.left;
        text.layoutMargin = ScreenObjectEdgeInsets(
          top: 0,
          left: 24,
          bottom: 24,
          right: 0,
        );
        mixer.screen?.addChild(text);
      }
      await mixer.startRunning();

      final session = await StreamSession.create(
        config.url,
        StreamSessionMode.publish,
      );
      final codec = VideoCodecSettings(
        width: q.width,
        height: q.height,
        bitrate: q.bitrate,
        frameInterval: 2, // YouTube wants a keyframe every 2 seconds.
        profileLevel: ProfileLevel.h264High40,
      );
      session.videoSettings = config.portrait ? codec.inverted() : codec;
      session.audioSettings = AudioCodecSettings(bitrate: 128 * 1000);
      _stateSub = session.readyState.listen(_onState);

      setState(() {
        _mixer = mixer;
        _session = session;
      });
    } catch (e) {
      setState(() => _error = 'Could not start the camera: $e');
    }
  }

  void _onState(StreamSessionReadyState s) {
    setState(() => _state = s);
    if (s == StreamSessionReadyState.open) {
      _liveSince ??= DateTime.now();
      WakelockPlus.enable();
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (s == StreamSessionReadyState.closed) {
      _ticker?.cancel();
      _ticker = null;
      _liveSince = null;
      WakelockPlus.disable();
    }
  }

  Future<void> _toggleLive() async {
    final session = _session;
    if (session == null) return;
    if (_state == StreamSessionReadyState.open ||
        _state == StreamSessionReadyState.connecting) {
      await session.close();
      return;
    }
    try {
      await session.connect();
    } on StreamSessionException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Could not go live'),
          content: Text(
            '${e.message}\n\nCheck the stream key, that the stream '
            'is set up in YouTube Studio, and your internet connection.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    final mixer = _mixer;
    if (mixer == null || _sources.length < 2) return;
    final want = _current?.position == CameraPosition.back
        ? CameraPosition.front
        : CameraPosition.back;
    final next = _sources.where((s) => s.position == want).firstOrNull;
    if (next == null) return;
    await mixer.attachVideo(0, next);
    setState(() => _current = next);
  }

  void _toggleMute() {
    final mixer = _mixer;
    if (mixer == null) return;
    _muted = !_muted;
    mixer.audioMixerSettings = mixer.audioMixerSettings.copyWith(
      isMuted: _muted,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final live = _state == StreamSessionReadyState.open;
    final connecting = _state == StreamSessionReadyState.connecting;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _session == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                  )
                : StreamSessionViewTexture(_session),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      OverlayButton(
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: live ? Colors.red : Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          live
                              ? 'LIVE ${formatDuration(DateTime.now().difference(_liveSince ?? DateTime.now()))}'
                              : connecting
                              ? 'CONNECTING...'
                              : 'OFFLINE  ${config.quality.label}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      OverlayButton(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        active: _muted,
                        onPressed: _toggleMute,
                      ),
                      const SizedBox(width: 8),
                      OverlayButton(
                        icon: Icons.cameraswitch,
                        onPressed: _switchCamera,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Center(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: live || connecting
                            ? Colors.grey[800]
                            : Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                      ),
                      onPressed: _session == null ? null : _toggleLive,
                      icon: Icon(
                        live || connecting ? Icons.stop : Icons.wifi_tethering,
                      ),
                      label: Text(
                        live || connecting ? 'End stream' : 'Go live',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

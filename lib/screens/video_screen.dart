import 'dart:async';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../modes/video_preset.dart';
import '../services/media_store.dart';
import '../widgets/common.dart';

/// Video recording with a YouTube oriented preset.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.preset});
  final VideoPreset preset;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _Chapter {
  _Chapter(this.at, this.title);
  final Duration at;
  String title;
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPreset get preset => widget.preset;

  bool _grid = true;
  double _ev = 0.5;
  int? _countdown;
  DateTime? _startedAt;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;
  Timer? _ticker;
  final List<_Chapter> _chapters = [];

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Duration get _elapsed {
    if (_startedAt == null) return Duration.zero;
    final now = DateTime.now();
    final pausedNow = _pausedAt == null
        ? Duration.zero
        : now.difference(_pausedAt!);
    return now.difference(_startedAt!) - _pausedTotal - pausedNow;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CameraAwesomeBuilder.custom(
        saveConfig: SaveConfig.video(
          videoOptions: preset.videoOptions,
          pathBuilder: (sensors) async => SingleCaptureRequest(
            await MediaStore.newPath(preset.id, 'mp4'),
            sensors.first,
          ),
        ),
        sensorConfig: SensorConfig.single(
          sensor: Sensor.position(preset.sensorPosition),
          aspectRatio: CameraAspectRatios.ratio_16_9,
        ),
        previewFit: CameraPreviewFit.contain,
        builder: (state, preview) => Stack(
          children: [
            if (_grid) const ThirdsGrid(),
            if (_countdown != null) CountdownOverlay(value: _countdown!),
            SafeArea(
              child:
                  state.when(
                    onVideoMode: (s) => _idleUi(s),
                    onVideoRecordingMode: (s) => _recordingUi(s),
                    onPreparingCamera: (_) =>
                        const Center(child: CircularProgressIndicator()),
                  ) ??
                  const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(List<Widget> actions) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        OverlayButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            preset.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...actions,
      ],
    ),
  );

  Widget _idleUi(VideoCameraState state) {
    return Column(
      children: [
        _header([
          OverlayButton(
            icon: Icons.grid_3x3,
            active: _grid,
            onPressed: () => setState(() => _grid = !_grid),
          ),
          const SizedBox(width: 6),
          AwesomeFlashButton(state: state),
          const SizedBox(width: 6),
          OverlayButton(
            icon: Icons.lightbulb_outline,
            onPressed: () => showTips(context, preset.name, preset.tips),
          ),
        ]),
        const Spacer(),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('EV', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: _ev,
                      onChanged: (v) {
                        setState(() => _ev = v);
                        state.sensorConfig.setBrightness(v);
                      },
                    ),
                  ),
                ],
              ),
              AwesomeZoomSelector(state: state),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 64),
              ShutterButton(
                color: Colors.red,
                busy: _countdown != null,
                onTap: () => _start(state),
              ),
              SizedBox(
                width: 64,
                child: AwesomeCameraSwitchButton(state: state),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recordingUi(VideoRecordingCameraState state) {
    final paused = _pausedAt != null;
    final over = preset.id == 'shorts' && _elapsed.inSeconds >= 60;
    return Column(
      children: [
        _header([
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: over ? Colors.red : Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${paused ? 'PAUSED ' : '● '}${formatDuration(_elapsed)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ]),
        if (_chapters.isNotEmpty)
          Text(
            'Step ${_chapters.length}: ${_chapters.last.title}',
            style: const TextStyle(color: Colors.white70),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 72,
                child: preset.chapters
                    ? OverlayButton(
                        icon: Icons.bookmark_add,
                        label: 'Mark step',
                        onPressed: _markStep,
                      )
                    : const SizedBox.shrink(),
              ),
              ShutterButton(recording: true, onTap: () => _stop(state)),
              SizedBox(
                width: 72,
                child: StreamBuilder<MediaCapture?>(
                  stream: state.captureState$,
                  builder: (_, snap) {
                    final capture = snap.data;
                    return OverlayButton(
                      icon: paused ? Icons.play_arrow : Icons.pause,
                      label: paused ? 'Resume' : 'Pause',
                      onPressed: capture == null
                          ? null
                          : () => _togglePause(state, capture),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _start(VideoCameraState state) async {
    for (var i = preset.countdownSeconds; i > 0; i--) {
      setState(() => _countdown = i);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }
    setState(() => _countdown = null);
    await WakelockPlus.enable();
    await state.startRecording();
    _startedAt = DateTime.now();
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _chapters
      ..clear()
      ..add(_Chapter(Duration.zero, 'Intro'));
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _markStep() {
    final at = _elapsed;
    setState(() => _chapters.add(_Chapter(at, 'Step ${_chapters.length}')));
    HapticFeedback.mediumImpact();
  }

  Future<void> _togglePause(
    VideoRecordingCameraState state,
    MediaCapture capture,
  ) async {
    if (_pausedAt == null) {
      await state.pauseRecording(capture);
      setState(() => _pausedAt = DateTime.now());
    } else {
      await state.resumeRecording(capture);
      setState(() {
        _pausedTotal += DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
      });
    }
  }

  Future<void> _stop(VideoRecordingCameraState state) async {
    _ticker?.cancel();
    final chapters = List<_Chapter>.of(_chapters);
    await state.stopRecording(
      onVideo: (req) async {
        final path = req.path;
        final saved = path != null && await MediaStore.saveVideo(path);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Video saved to your gallery.'
                  : 'Could not save the video to the gallery.',
            ),
          ),
        );
        if (preset.chapters && chapters.length > 1) {
          await _showChapters(chapters);
        }
      },
    );
    await WakelockPlus.disable();
    _startedAt = null;
    if (mounted) setState(() {});
  }

  Future<void> _showChapters(List<_Chapter> chapters) async {
    final controllers = [
      for (final c in chapters) TextEditingController(text: c.title),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('YouTube chapters', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Rename the steps, then copy and paste into your video description. '
              'YouTube needs at least 3 chapters, each 10 seconds or longer.',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < chapters.length; i++)
                    Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(formatDuration(chapters[i].at)),
                        ),
                        Expanded(child: TextField(controller: controllers[i])),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy chapters'),
              onPressed: () {
                final text = [
                  for (var i = 0; i < chapters.length; i++)
                    '${formatDuration(chapters[i].at)} ${controllers[i].text}',
                ].join('\n');
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
  }
}

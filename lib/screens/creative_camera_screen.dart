import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../modes/shoot_mode.dart';
import '../processing/hdr_fusion.dart';
import '../processing/stack_engine.dart';
import '../processing/stack_worker.dart';
import '../services/media_store.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Camera screen for every photo mode: stacking modes, HDR and pro photo.
class CreativeCameraScreen extends StatefulWidget {
  const CreativeCameraScreen({super.key, required this.mode});
  final ShootMode mode;

  @override
  State<CreativeCameraScreen> createState() => _CreativeCameraScreenState();
}

enum _Phase { idle, countdown, capturing, processing }

class _CreativeCameraScreenState extends State<CreativeCameraScreen> {
  ShootMode get mode => widget.mode;

  _Phase _phase = _Phase.idle;
  int _countdown = 0;
  int _timerSeconds = 0;
  bool _grid = true;
  double _ev = 0.5;
  int _threshold = 0;
  String _status = '';

  StackWorker? _worker;
  StreamSubscription<StackPreview>? _previewSub;
  ui.Image? _live;
  int _liveRotation = 0;
  int _frames = 0;
  int _rotation = 0;
  DateTime? _startedAt;
  Timer? _ticker;
  CameraState? _state;

  @override
  void initState() {
    super.initState();
    _threshold = mode.stack?.lightenThreshold ?? 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _previewSub?.cancel();
    _worker?.dispose();
    _live?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  bool get _isStack => mode.kind == ModeKind.stack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CameraAwesomeBuilder.custom(
        saveConfig: SaveConfig.photo(
          pathBuilder: (sensors) async => SingleCaptureRequest(
            await MediaStore.newPath(mode.id, 'jpg'),
            sensors.first,
          ),
        ),
        sensorConfig: SensorConfig.single(
          sensor: Sensor.position(SensorPosition.back),
          aspectRatio: CameraAspectRatios.ratio_4_3,
        ),
        previewFit: CameraPreviewFit.contain,
        onImageForAnalysis: _isStack ? _onFrame : null,
        imageAnalysisConfig: _isStack
            ? AnalysisConfig(
                autoStart: false,
                maxFramesPerSecond: mode.analysisFps,
                androidOptions: AndroidAnalysisOptions.bgra8888(
                  width: mode.analysisWidth,
                ),
                cupertinoOptions: const CupertinoAnalysisOptions.bgra8888(),
              )
            : null,
        builder: (state, preview) {
          _state = state;
          return _overlay(state);
        },
      ),
    );
  }

  Widget _overlay(CameraState state) {
    final busy = _phase == _Phase.processing;
    return Stack(
      children: [
        if (_grid) const ThirdsGrid(),
        if (_live != null && _phase != _Phase.idle)
          Positioned.fill(
            child: IgnorePointer(
              child: RotatedBox(
                quarterTurns: _liveRotation ~/ 90,
                child: RawImage(image: _live, fit: BoxFit.contain),
              ),
            ),
          ),
        if (_phase == _Phase.countdown) CountdownOverlay(value: _countdown),
        SafeArea(
          child: Column(
            children: [
              _topBar(state),
              if (_status.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _status,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              const Spacer(),
              if (_phase == _Phase.idle) _sliders(state),
              _bottomBar(state, busy),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(CameraState state) {
    return Padding(
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
              mode.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OverlayButton(
            icon: Icons.grid_3x3,
            active: _grid,
            onPressed: () => setState(() => _grid = !_grid),
          ),
          const SizedBox(width: 6),
          OverlayButton(
            icon: Icons.timer,
            active: _timerSeconds > 0,
            label: _timerSeconds == 0 ? 'off' : '${_timerSeconds}s',
            onPressed: () => setState(
              () => _timerSeconds = _timerSeconds == 0
                  ? 3
                  : (_timerSeconds == 3 ? 10 : 0),
            ),
          ),
          const SizedBox(width: 6),
          if (mode.kind == ModeKind.photo) ...[
            AwesomeFlashButton(state: state),
            const SizedBox(width: 6),
          ],
          OverlayButton(
            icon: Icons.lightbulb_outline,
            onPressed: () => showTips(context, mode.name, mode.tips),
          ),
        ],
      ),
    );
  }

  Widget _sliders(CameraState state) {
    final showThreshold = mode.stack?.blend == StackBlend.lighten;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _labelledSlider('EV', _ev, 0, 1, (v) {
            setState(() => _ev = v);
            state.sensorConfig.setBrightness(v);
          }, ((_ev - 0.5) * 4).toStringAsFixed(1)),
          if (showThreshold)
            _labelledSlider(
              'Light threshold',
              _threshold.toDouble(),
              0,
              200,
              (v) => setState(() => _threshold = v.round()),
              '$_threshold',
            ),
          AwesomeZoomSelector(state: state),
        ],
      ),
    );
  }

  Widget _labelledSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String text,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 36,
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(CameraState state, bool busy) {
    final capturing = _phase == _Phase.capturing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 64,
            child: capturing && _isStack
                ? Text(
                    '$_frames\nframes',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  )
                : const SizedBox.shrink(),
          ),
          ShutterButton(
            busy: busy,
            recording: capturing && _isStack,
            color: mode.color,
            onTap: () => _onShutter(state),
          ),
          SizedBox(
            width: 64,
            child: _phase == _Phase.idle
                ? AwesomeCameraSwitchButton(state: state)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- capture

  Future<void> _onShutter(CameraState state) async {
    if (_phase == _Phase.capturing && _isStack) {
      await _finishStack();
      return;
    }
    if (_phase != _Phase.idle) return;
    if (_timerSeconds > 0) {
      setState(() {
        _phase = _Phase.countdown;
        _countdown = _timerSeconds;
      });
      while (_countdown > 0) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() => _countdown--);
      }
    }
    switch (mode.kind) {
      case ModeKind.stack:
        await _startStack(state);
      case ModeKind.hdr:
        await _captureHdr(state);
      case ModeKind.photo:
        await _capturePhoto(state);
    }
  }

  Future<void> _startStack(CameraState state) async {
    final base = mode.stack!;
    final options = StackOptions(
      blend: base.blend,
      align: base.align,
      maxFrames: mode.autoStopFrames,
      echoDecay: base.echoDecay,
      slitWidth: base.slitWidth,
      lightenThreshold: _threshold,
    );
    final worker = await StackWorker.spawn(options);
    _previewSub = worker.previews.listen(_showPreview);
    await WakelockPlus.enable();
    setState(() {
      _worker = worker;
      _frames = 0;
      _phase = _Phase.capturing;
      _startedAt = DateTime.now();
      _status = mode.isOpenEnded
          ? 'Capturing. Tap stop when done.'
          : 'Hold still...';
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != _Phase.capturing) return;
      final s = DateTime.now().difference(_startedAt!);
      setState(
        () => _status = mode.isOpenEnded
            ? '${formatDuration(s)}  Tap stop when done.'
            : 'Hold still... ${(_frames * 100 / mode.autoStopFrames).round()}%',
      );
    });
    await state.analysisController?.start();
  }

  Future<void> _onFrame(AnalysisImage image) async {
    final worker = _worker;
    if (_phase != _Phase.capturing || worker == null) return;
    if (image is! Bgra8888Image || image.planes.isEmpty) return;
    final plane = image.planes.first;
    final stride = plane.bytesPerRow > 0 ? plane.bytesPerRow : image.width * 4;
    _rotation = _degrees(image.rotation);
    final (count, full) = await worker.addFrame(
      RawFrame(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: stride,
        isBgra: Platform.isIOS,
      ),
    );
    if (!mounted) return;
    setState(() => _frames = count);
    if (full && _phase == _Phase.capturing) unawaited(_finishStack());
  }

  void _showPreview(StackPreview p) {
    ui.decodeImageFromPixels(
      p.rgba,
      p.width,
      p.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _live?.dispose();
          _live = image;
          _liveRotation = _rotation;
        });
      },
    );
  }

  Future<void> _finishStack() async {
    final worker = _worker;
    if (worker == null || _phase != _Phase.capturing) return;
    _ticker?.cancel();
    setState(() {
      _phase = _Phase.processing;
      _status = 'Rendering $_frames frames...';
    });
    await _state?.analysisController?.stop();
    final path = await worker.finish(
      path: await MediaStore.newPath(mode.id, 'jpg'),
      rotationDegrees: _rotation,
      night: mode.nightTone,
    );
    await _previewSub?.cancel();
    worker.dispose();
    _worker = null;
    await WakelockPlus.disable();
    await _deliver(path);
  }

  Future<void> _captureHdr(CameraState state) async {
    final photo = state is PhotoCameraState ? state : null;
    if (photo == null) return;
    final original = _ev;
    final paths = <String>[];
    setState(() => _phase = _Phase.processing);
    try {
      for (final (i, ev) in [0.2, 0.5, 0.8].indexed) {
        setState(() => _status = 'Bracket ${i + 1} of 3. Hold still...');
        state.sensorConfig.setBrightness(ev);
        // setBrightness is debounced by 500 ms, then auto exposure settles.
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        final req = await photo.takePhoto();
        if (req.path != null) paths.add(req.path!);
      }
      state.sensorConfig.setBrightness(original);
      if (paths.length < 2) {
        await _deliver(null);
        return;
      }
      setState(() => _status = 'Fusing exposures...');
      final out = await HdrFusion.fuseFiles(
        paths,
        await MediaStore.newPath('hdr', 'jpg'),
      );
      await _deliver(out);
    } catch (e) {
      state.sensorConfig.setBrightness(original);
      await _deliver(null, error: '$e');
    }
  }

  Future<void> _capturePhoto(CameraState state) async {
    final photo = state is PhotoCameraState ? state : null;
    if (photo == null) return;
    setState(() => _phase = _Phase.processing);
    final req = await photo.takePhoto();
    await _deliver(req.path);
  }

  Future<void> _deliver(String? path, {String? error}) async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = '';
      _live?.dispose();
      _live = null;
    });
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Nothing was captured. Try again.')),
      );
      return;
    }
    final saved = await MediaStore.saveImage(path);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ResultScreen(path: path, savedToGallery: saved, title: mode.name),
      ),
    );
  }

  static int _degrees(InputAnalysisImageRotation r) => switch (r) {
    InputAnalysisImageRotation.rotation0deg => 0,
    InputAnalysisImageRotation.rotation90deg => 90,
    InputAnalysisImageRotation.rotation180deg => 180,
    InputAnalysisImageRotation.rotation270deg => 270,
  };
}

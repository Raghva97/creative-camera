import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../modes/shoot_mode.dart';
import '../processing/hdr_fusion.dart';
import '../processing/stack_engine.dart';
import '../processing/stack_worker.dart';
import '../services/media_store.dart';
import '../widgets/camera_overlays.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Camera screen for every photo mode. Each mode brings its own settings
/// bar (exposure length, frames, trail length, bracket...), its own guides
/// (level, slit line, shake meter) and its own capture logic.
class CreativeCameraScreen extends StatefulWidget {
  const CreativeCameraScreen({super.key, required this.mode});
  final ShootMode mode;

  @override
  State<CreativeCameraScreen> createState() => _CreativeCameraScreenState();
}

enum _Phase { idle, countdown, capturing, processing }

const _evId = '_ev';

class _CreativeCameraScreenState extends State<CreativeCameraScreen> {
  ShootMode get mode => widget.mode;

  _Phase _phase = _Phase.idle;
  int _countdown = 0;
  int _timerSeconds = 0;
  GridStyle _grid = GridStyle.thirds;
  late bool _level = mode.overlay == ModeOverlay.level;
  late double _ev = mode.defaultEv;
  final Map<String, num> _values = {};
  String? _openSetting;
  String _status = '';
  String? _lastCapture;

  StackWorker? _worker;
  StreamSubscription<StackPreview>? _previewSub;
  ui.Image? _live;
  int _liveRotation = 0;
  int _frames = 0;
  int _targetFrames = 0;
  int _rotation = 0;
  DateTime? _startedAt;
  DateTime _lastKept = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _ticker;
  CameraState? _state;
  bool _evApplied = false;
  int _bracketIndex = -1;
  List<double> _brackets = const [];

  @override
  void initState() {
    super.initState();
    for (final s in mode.settings) {
      _values[s.id] = s.options[s.initial].value;
    }
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
  bool get _busy => _phase != _Phase.idle;
  num? _v(String id) => _values[id];

  int get _durationSeconds => (_v(S.duration) ?? 0).toInt();
  double get _interval => (_v(S.interval) ?? 0).toDouble();

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
          if (!_evApplied && state is! PreparingCameraState) {
            _evApplied = true;
            state.sensorConfig.setBrightness(_ev);
          }
          return _overlay(state);
        },
      ),
    );
  }

  // ------------------------------------------------------------------ layout

  Widget _overlay(CameraState state) {
    final capturing = _phase == _Phase.capturing;
    return Stack(
      children: [
        CompositionGrid(style: _grid),
        if (mode.overlay == ModeOverlay.slitLine && !capturing)
          SlitLine(vertical: (_v(S.direction) ?? 1) == 1, color: mode.color),
        if (_level && !capturing) const LevelIndicator(),
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
              if (mode.overlay == ModeOverlay.shakeMeter)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: ShakeMeter(),
                ),
              if (_status.isNotEmpty) _statusPill(),
              if (_brackets.isNotEmpty) _bracketPills(),
              const Spacer(),
              if (!_busy) ...[
                if (_openSetting != null) _optionsPanel(state),
                _settingsBar(),
                const SizedBox(height: 6),
                AwesomeZoomSelector(state: state),
              ],
              if (capturing) _progress(),
              _shutterRow(state),
              if (!_busy) _modeStrip(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(CameraState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          OverlayButton(
            icon: Icons.arrow_back,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(mode.icon, color: mode.color, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        mode.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  mode.hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_busy) ...[
            _smallButton(
              _grid.icon,
              _grid.label,
              () => setState(() => _grid = _grid.next),
              active: _grid != GridStyle.off,
            ),
            _smallButton(
              Icons.straighten,
              'Level',
              () => setState(() => _level = !_level),
              active: _level,
            ),
            _smallButton(
              Icons.timer,
              _timerSeconds == 0 ? 'Timer' : '${_timerSeconds}s',
              () => setState(
                () => _timerSeconds = switch (_timerSeconds) {
                  0 => 3,
                  3 => 10,
                  _ => 0,
                },
              ),
              active: _timerSeconds > 0,
            ),
            if (mode.kind == ModeKind.photo) AwesomeFlashButton(state: state),
            _smallButton(
              Icons.lightbulb_outline,
              'Tips',
              () => showTips(context, mode.name, mode.tips),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final color = active ? mode.color : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _statusPill() => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _status,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
    ),
  );

  Widget _bracketPills() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in _brackets.indexed)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: i == _bracketIndex
                  ? mode.color
                  : (i < _bracketIndex ? Colors.white24 : Colors.black54),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _evLabel(b),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  /// Chips for EV and every mode specific setting.
  Widget _settingsBar() {
    final chips = <Widget>[
      _chip(_evId, Icons.exposure, 'EV', _evLabel(_ev)),
      for (final s in mode.settings)
        _chip(
          s.id,
          s.icon,
          s.label,
          s.options
              .firstWhere(
                (o) => o.value == _values[s.id],
                orElse: () => s.options[s.initial],
              )
              .label,
        ),
    ];
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: chips,
      ),
    );
  }

  Widget _chip(String id, IconData icon, String label, String value) {
    final open = _openSetting == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _openSetting = open ? null : id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: open ? mode.color : Colors.black54,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: open ? mode.color : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: open ? Colors.black : Colors.white),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: open ? Colors.black87 : Colors.white70,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: open ? Colors.black : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionsPanel(CameraState state) {
    final id = _openSetting!;
    final Widget body;
    String? help;
    if (id == _evId) {
      help =
          'Exposure compensation. Darker keeps highlights and makes '
          'lights stand out; brighter lifts shadows.';
      body = Slider(
        value: _ev,
        divisions: 20,
        label: _evLabel(_ev),
        activeColor: mode.color,
        onChanged: (v) {
          setState(() => _ev = v);
          state.sensorConfig.setBrightness(v);
        },
      );
    } else {
      final s = mode.settings.firstWhere((s) => s.id == id);
      help = s.help;
      body = Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final o in s.options)
            ChoiceChip(
              label: Text(o.label),
              selected: _values[id] == o.value,
              selectedColor: mode.color,
              onSelected: (_) => _select(state, s, o),
            ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(
              help,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  void _select(CameraState state, ModeSetting s, SettingOption o) {
    setState(() => _values[s.id] = o.value);
    HapticFeedback.selectionClick();
    if (s.id == S.aspect) {
      state.sensorConfig.setAspectRatio(
        o.value == 1
            ? CameraAspectRatios.ratio_16_9
            : CameraAspectRatios.ratio_4_3,
      );
    }
  }

  Widget _progress() {
    double? value;
    if (_targetFrames > 0) {
      value = _frames / _targetFrames;
    } else if (_durationSeconds > 0 && _startedAt != null) {
      value =
          DateTime.now().difference(_startedAt!).inMilliseconds /
          (_durationSeconds * 1000);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 0),
      child: LinearProgressIndicator(
        value: value?.clamp(0.0, 1.0),
        color: mode.color,
        backgroundColor: Colors.white24,
        minHeight: 4,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _shutterRow(CameraState state) {
    final capturing = _phase == _Phase.capturing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: capturing
                ? Center(
                    child: Text(
                      '$_frames\nframes',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                : _thumbnail(),
          ),
          ShutterButton(
            busy: _phase == _Phase.processing,
            recording: capturing && _isStack,
            color: mode.color,
            onTap: () => _onShutter(state),
          ),
          SizedBox(
            width: 56,
            child: _busy
                ? const SizedBox.shrink()
                : AwesomeCameraSwitchButton(state: state),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail() {
    final path = _lastCapture;
    if (path == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _openResult(path, true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 160),
      ),
    );
  }

  /// Horizontal list of all photo modes, like a stock camera app.
  Widget _modeStrip() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final m in photoModes)
            GestureDetector(
              onTap: m.id == mode.id ? null : () => _switchMode(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  m.name.toUpperCase(),
                  style: TextStyle(
                    color: m.id == mode.id ? m.color : Colors.white70,
                    fontWeight: m.id == mode.id
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _switchMode(ShootMode m) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => CreativeCameraScreen(mode: m),
        transitionDuration: Duration.zero,
      ),
    );
  }

  static String _evLabel(double v) {
    final ev = (v - 0.5) * 4;
    return '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)}';
  }

  // ---------------------------------------------------------------- capture

  Future<void> _onShutter(CameraState state) async {
    if (_phase == _Phase.capturing && _isStack) {
      await _finishStack();
      return;
    }
    if (_phase != _Phase.idle) return;
    setState(() => _openSetting = null);
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
    var maxFrames = (_v(S.frames) ?? 0).toInt();
    if (base.blend == StackBlend.median && _durationSeconds > 0) {
      maxFrames = (_durationSeconds / (_interval > 0 ? _interval : 1)).round();
    }
    final options = StackOptions(
      blend: base.blend,
      align: _v(S.align) != null ? _v(S.align) == 1 : base.align,
      maxFrames: maxFrames,
      echoDecay: (_v(S.decay) ?? base.echoDecay).toDouble(),
      slitWidth: (_v(S.slit) ?? base.slitWidth).toInt(),
      slitDisplayVertical: (_v(S.direction) ?? 1) == 1,
      lightenThreshold: (_v(S.threshold) ?? base.lightenThreshold).toInt(),
    );
    final worker = await StackWorker.spawn(options);
    _previewSub = worker.previews.listen(_showPreview);
    await WakelockPlus.enable();
    setState(() {
      _worker = worker;
      _frames = 0;
      _targetFrames = maxFrames;
      _phase = _Phase.capturing;
      _startedAt = DateTime.now();
      _lastKept = DateTime.fromMillisecondsSinceEpoch(0);
      _status = _captureStatus();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _phase != _Phase.capturing) return;
      final elapsed = DateTime.now().difference(_startedAt!);
      if (_durationSeconds > 0 && elapsed.inSeconds >= _durationSeconds) {
        unawaited(_finishStack());
        return;
      }
      setState(() => _status = _captureStatus());
    });
    await state.analysisController?.start();
  }

  String _captureStatus() {
    final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    if (mode.stack?.blend == StackBlend.slitScan) {
      return 'Scanning... keep the motion going';
    }
    if (_targetFrames > 0) {
      return mode.overlay == ModeOverlay.shakeMeter
          ? 'Hold still  $_frames / $_targetFrames'
          : 'Frame $_frames / $_targetFrames';
    }
    if (_durationSeconds > 0) {
      return '${formatDuration(elapsed)} / '
          '${formatDuration(Duration(seconds: _durationSeconds))}';
    }
    return 'BULB  ${formatDuration(elapsed)}  Tap stop when done';
  }

  Future<void> _onFrame(AnalysisImage image) async {
    final worker = _worker;
    if (_phase != _Phase.capturing || worker == null) return;
    if (image is! Bgra8888Image || image.planes.isEmpty) return;
    final now = DateTime.now();
    if (_interval > 0 &&
        now.difference(_lastKept).inMilliseconds < _interval * 1000 - 30) {
      return;
    }
    _lastKept = now;
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
      rotationDegrees: _rotation,
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
      nightGain: (_v(S.boost) ?? 4).toDouble(),
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
    final spread = (_v(S.bracket) ?? 0.3).toDouble();
    final shots = (_v(S.shots) ?? 3).toInt();
    final brackets = shots == 5
        ? [-spread, -spread / 2, 0.0, spread / 2, spread]
        : [-spread, 0.0, spread];
    final paths = <String>[];
    setState(() {
      _phase = _Phase.processing;
      _brackets = [for (final b in brackets) (_ev + b).clamp(0.0, 1.0)];
    });
    try {
      for (var i = 0; i < _brackets.length; i++) {
        setState(() {
          _bracketIndex = i;
          _status = 'Shot ${i + 1} of ${_brackets.length}. Hold still...';
        });
        state.sensorConfig.setBrightness(_brackets[i]);
        // setBrightness is debounced by 500 ms, then auto exposure settles.
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        final req = await photo.takePhoto();
        if (req.path != null) paths.add(req.path!);
      }
      state.sensorConfig.setBrightness(_ev);
      if (paths.length < 2) {
        await _deliver(null);
        return;
      }
      setState(() {
        _bracketIndex = _brackets.length;
        _status = 'Fusing ${paths.length} exposures...';
      });
      final out = await HdrFusion.fuseFiles(
        paths,
        await MediaStore.newPath('hdr', 'jpg'),
      );
      await _deliver(out);
    } catch (e) {
      state.sensorConfig.setBrightness(_ev);
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
      _brackets = const [];
      _bracketIndex = -1;
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
    setState(() => _lastCapture = path);
    await _openResult(path, saved);
  }

  Future<void> _openResult(String path, bool saved) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          ResultScreen(path: path, savedToGallery: saved, title: mode.name),
    ),
  );

  static int _degrees(InputAnalysisImageRotation r) => switch (r) {
    InputAnalysisImageRotation.rotation0deg => 0,
    InputAnalysisImageRotation.rotation90deg => 90,
    InputAnalysisImageRotation.rotation180deg => 180,
    InputAnalysisImageRotation.rotation270deg => 270,
  };
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'stack_engine.dart';
import 'tone.dart';

/// Live preview produced by the worker while frames are being stacked.
class StackPreview {
  StackPreview(this.rgba, this.width, this.height, this.frames);
  final Uint8List rgba;
  final int width;
  final int height;
  final int frames;
}

/// Runs a [StackEngine] in a background isolate so the camera preview and
/// UI stay smooth while megapixel frames are being blended.
class StackWorker {
  StackWorker._(this._isolate, this._send);

  final Isolate _isolate;
  final SendPort _send;
  final _previews = StreamController<StackPreview>.broadcast();
  Completer<dynamic>? _pending;

  Stream<StackPreview> get previews => _previews.stream;

  static Future<StackWorker> spawn(StackOptions options) async {
    final rp = ReceivePort();
    final iso = await Isolate.spawn(_main, rp.sendPort);
    final replies = rp.asBroadcastStream();
    final send = await replies.first as SendPort;
    final w = StackWorker._(iso, send);
    replies.listen(w._onReply);
    send.send({'cmd': 'init', 'options': options.toMap()});
    return w;
  }

  void _onReply(dynamic msg) {
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'preview':
        final data = (msg['data'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        _previews.add(
          StackPreview(
            data,
            msg['w'] as int,
            msg['h'] as int,
            msg['frames'] as int,
          ),
        );
      default:
        final p = _pending;
        _pending = null;
        p?.complete(msg);
    }
  }

  Future<Map> _request(Map<String, Object?> msg) {
    final c = Completer<dynamic>();
    _pending = c;
    _send.send(msg);
    return c.future.then((v) => v as Map);
  }

  /// Sends a frame and waits until it has been blended. Returns the frame
  /// count and whether the engine has all the frames it wants.
  Future<(int, bool)> addFrame(RawFrame f, {int rotationDegrees = 0}) async {
    final reply = await _request({
      'cmd': 'frame',
      'data': TransferableTypedData.fromList([f.bytes]),
      'w': f.width,
      'h': f.height,
      'stride': f.bytesPerRow,
      'bgra': f.isBgra,
      'rotation': rotationDegrees,
    });
    return (reply['frames'] as int, reply['full'] as bool);
  }

  /// Renders the final picture, writes it as JPEG to [path] and returns it.
  Future<String?> finish({
    required String path,
    required int rotationDegrees,
    bool night = false,
    double nightGain = 4.0,
  }) async {
    final reply = await _request({
      'cmd': 'finish',
      'path': path,
      'rotation': rotationDegrees,
      'night': night,
      'gain': nightGain,
    });
    return reply['path'] as String?;
  }

  void dispose() {
    _previews.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _main(SendPort out) {
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    StackEngine? engine;
    var lastPreview = DateTime.fromMillisecondsSinceEpoch(0);

    inbox.listen((dynamic raw) {
      final msg = raw as Map;
      switch (msg['cmd']) {
        case 'init':
          engine = StackEngine(StackOptions.fromMap(msg['options'] as Map));
        case 'frame':
          final e = engine!;
          if (e.frameCount == 0) e.rotationDegrees = msg['rotation'] as int;
          final bytes = (msg['data'] as TransferableTypedData)
              .materialize()
              .asUint8List();
          e.add(
            RawFrame(
              bytes: bytes,
              width: msg['w'] as int,
              height: msg['h'] as int,
              bytesPerRow: msg['stride'] as int,
              isBgra: msg['bgra'] as bool,
            ),
          );
          final now = DateTime.now();
          // Previews are throttled: building one costs a full pass.
          if (now.difference(lastPreview).inMilliseconds > 350) {
            lastPreview = now;
            final (rgba, w, h) = previewRgba(e.result(), 480);
            out.send({
              'type': 'preview',
              'data': TransferableTypedData.fromList([rgba]),
              'w': w,
              'h': h,
              'frames': e.frameCount,
            });
          }
          out.send({'type': 'ack', 'frames': e.frameCount, 'full': e.isFull});
        case 'finish':
          final e = engine;
          if (e == null || e.frameCount == 0) {
            out.send({'type': 'done', 'path': null});
            return;
          }
          var result = e.result();
          if (msg['night'] == true) {
            result = nightTone(
              result,
              maxGain: (msg['gain'] as num).toDouble(),
            );
          }
          final im = toImage(result, msg['rotation'] as int);
          final path = msg['path'] as String;
          File(path).writeAsBytesSync(img.encodeJpg(im, quality: 95));
          out.send({'type': 'done', 'path': path});
      }
    });
  }
}

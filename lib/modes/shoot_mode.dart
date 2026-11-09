import 'package:flutter/material.dart';

import '../processing/stack_engine.dart';

/// How a mode produces its result.
enum ModeKind {
  /// Frames from the live analysis stream are blended in a worker.
  stack,

  /// Several full resolution photos at different exposures are fused.
  hdr,

  /// Plain photo with the pro overlay (grid, timer, exposure).
  photo,
}

/// Extra guide drawn over the preview for a mode.
enum ModeOverlay { none, slitLine, level, shakeMeter }

/// One choice of a [ModeSetting].
class SettingOption {
  const SettingOption(this.label, this.value);
  final String label;
  final num value;
}

/// A control specific to one mode (exposure length, number of frames,
/// trail length...). Shown as a chip in the mode's settings bar.
class ModeSetting {
  const ModeSetting({
    required this.id,
    required this.label,
    required this.icon,
    required this.options,
    this.initial = 0,
    this.help,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<SettingOption> options;

  /// Index into [options] used when the mode opens.
  final int initial;
  final String? help;
}

/// Setting ids understood by the camera screen.
abstract final class S {
  /// Seconds the capture runs; 0 means bulb (until the user stops it).
  static const duration = 'duration';

  /// Number of frames to stack.
  static const frames = 'frames';

  /// Luminance a pixel must exceed to add light (lighten modes).
  static const threshold = 'threshold';

  /// Seconds between kept frames; 0 keeps every frame.
  static const interval = 'interval';

  /// Echo trail persistence (0..1).
  static const decay = 'decay';

  /// Slit width in pixels per frame (time slice speed).
  static const slit = 'slit';

  /// 1 = vertical slit sweeping left to right, 0 = horizontal.
  static const direction = 'direction';

  /// 1 = handheld (align frames), 0 = tripod.
  static const align = 'align';

  /// Night brightening gain cap.
  static const boost = 'boost';

  /// HDR bracket spread on CamerAwesome's 0..1 brightness scale.
  static const bracket = 'bracket';

  /// Number of HDR brackets.
  static const shots = 'shots';

  /// 0 = 4:3, 1 = 16:9.
  static const aspect = 'aspect';
}

const _bulbDurations = [
  SettingOption('Bulb', 0),
  SettingOption('5s', 5),
  SettingOption('10s', 10),
  SettingOption('20s', 20),
  SettingOption('30s', 30),
  SettingOption('60s', 60),
];

const _support = ModeSetting(
  id: S.align,
  label: 'Support',
  icon: Icons.back_hand_outlined,
  options: [SettingOption('Handheld', 1), SettingOption('Tripod', 0)],
  help:
      'Handheld aligns every frame to the first. Tripod skips that for '
      'speed and the sharpest result.',
);

/// One "way to click": a recipe of capture settings plus advice on how to
/// get a great shot with it.
class ShootMode {
  const ShootMode({
    required this.id,
    required this.name,
    required this.tagline,
    required this.hint,
    required this.icon,
    required this.color,
    required this.kind,
    this.stack,
    this.analysisFps = 15,
    this.analysisWidth = 1280,
    this.nightTone = false,
    this.overlay = ModeOverlay.none,
    this.defaultEv = 0.5,
    this.settings = const [],
    this.tips = const [],
  });

  final String id;
  final String name;
  final String tagline;

  /// One line of guidance shown on the camera screen.
  final String hint;
  final IconData icon;
  final Color color;
  final ModeKind kind;
  final StackOptions? stack;

  /// Highest frame rate the mode asks the camera for. Slower settings
  /// (intervals) drop frames in Dart.
  final double analysisFps;

  /// Android only: width of frames requested from CameraX. iOS sends the
  /// session's native video size.
  final int analysisWidth;
  final bool nightTone;
  final ModeOverlay overlay;

  /// Exposure compensation on CamerAwesome's 0..1 scale (0.5 = neutral).
  final double defaultEv;
  final List<ModeSetting> settings;
  final List<String> tips;
}

const photoModes = <ShootMode>[
  ShootMode(
    id: 'light_painting',
    name: 'Light Painting',
    tagline: 'Draw with a torch, phone light or sparkler',
    hint: 'Tripod, dark scene. Start, then draw in the air with a light.',
    icon: Icons.auto_fix_high,
    color: Color(0xFFFFB300),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten),
    defaultEv: 0.35,
    settings: [
      ModeSetting(
        id: S.duration,
        label: 'Exposure',
        icon: Icons.shutter_speed,
        options: _bulbDurations,
        help: 'Bulb keeps the shutter open until you tap stop.',
      ),
      ModeSetting(
        id: S.threshold,
        label: 'Light only',
        icon: Icons.flare,
        options: [
          SettingOption('Off', 0),
          SettingOption('Low', 40),
          SettingOption('Medium', 80),
          SettingOption('High', 140),
        ],
        initial: 2,
        help:
            'Only pixels brighter than this can add light, so the room '
            'stays dark and only your light strokes are recorded.',
      ),
    ],
    tips: [
      'Put the phone on a tripod or lean it on something solid. It must not move.',
      'Work in a dark room or outdoors at night. Only the moving light should be bright.',
      'Lower exposure (EV) until the background is nearly black.',
      'Press start, then walk into the frame and draw. Wear dark clothes so you stay invisible.',
      'Raise "Light only" if the background slowly brightens; lower it for faint lights.',
    ],
  ),
  ShootMode(
    id: 'light_trails',
    name: 'Light Trails',
    tagline: 'Car headlights and tail lights become ribbons',
    hint: 'Tripod above traffic at dusk. Let several cars pass.',
    icon: Icons.route,
    color: Color(0xFFE53935),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten),
    settings: [
      ModeSetting(
        id: S.duration,
        label: 'Exposure',
        icon: Icons.shutter_speed,
        options: _bulbDurations,
        initial: 4,
      ),
      ModeSetting(
        id: S.threshold,
        label: 'Light only',
        icon: Icons.flare,
        options: [
          SettingOption('Off', 0),
          SettingOption('Low', 40),
          SettingOption('Medium', 80),
        ],
        help:
            'Off keeps the whole scene (buildings, sky). Higher values '
            'keep only the bright car lights.',
      ),
    ],
    tips: [
      'Tripod needed. Find a bridge, roadside or balcony overlooking traffic.',
      'Shoot at dusk (blue hour) so the sky still has colour.',
      'Let it run 20 to 60 seconds so several cars pass through.',
      'Include a static, lit subject (building, street lamp) to anchor the picture.',
    ],
  ),
  ShootMode(
    id: 'long_exposure',
    name: 'Silky Water',
    tagline: 'Long exposure: waterfalls, waves, clouds',
    hint: 'Moving water turns smooth. Keep the phone still.',
    icon: Icons.water,
    color: Color(0xFF039BE5),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.average),
    settings: [
      ModeSetting(
        id: S.frames,
        label: 'Smoothness',
        icon: Icons.waves,
        options: [
          SettingOption('Light 2s', 30),
          SettingOption('Medium 4s', 60),
          SettingOption('Strong 8s', 120),
        ],
        initial: 1,
        help: 'How long the simulated shutter stays open.',
      ),
      _support,
    ],
    tips: [
      'Works in daylight with no ND filter: the app averages many frames.',
      'Tripod gives the sharpest rocks; handheld works thanks to alignment.',
      'Moving water, waves and drifting clouds turn smooth. Still things stay sharp.',
      'More smoothness means silkier water. Less keeps some texture.',
    ],
  ),
  ShootMode(
    id: 'night',
    name: 'Night',
    tagline: 'Bright, clean photos in low light',
    hint: 'Hold still while frames are collected.',
    icon: Icons.nightlight_round,
    color: Color(0xFF5E35B1),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.average),
    analysisFps: 20,
    analysisWidth: 1920,
    nightTone: true,
    overlay: ModeOverlay.shakeMeter,
    settings: [
      ModeSetting(
        id: S.frames,
        label: 'Frames',
        icon: Icons.burst_mode,
        options: [
          SettingOption('8 (fast)', 8),
          SettingOption('16', 16),
          SettingOption('24', 24),
          SettingOption('48 (tripod)', 48),
        ],
        initial: 2,
        help: 'More frames remove more noise but take longer to hold still.',
      ),
      ModeSetting(
        id: S.boost,
        label: 'Brightness',
        icon: Icons.brightness_6,
        options: [
          SettingOption('Natural', 2),
          SettingOption('Bright', 4),
          SettingOption('Max', 8),
        ],
        initial: 1,
        help: 'How far dark scenes are brightened after stacking.',
      ),
      _support,
    ],
    tips: [
      'Hold still for about 2 seconds while frames are collected, or brace on a wall.',
      'The app aligns and averages the frames to remove noise, then brightens them.',
      'Turn flash off. Street lights, neon and city skylines look best.',
      'Tap the subject to focus before starting.',
    ],
  ),
  ShootMode(
    id: 'star_trails',
    name: 'Star Trails',
    tagline: 'Stars draw circles as the Earth turns',
    hint: 'Tripod, dark sky, point north. Leave it running.',
    icon: Icons.star,
    color: Color(0xFF283593),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten),
    analysisFps: 4,
    analysisWidth: 1920,
    defaultEv: 0.8,
    settings: [
      ModeSetting(
        id: S.duration,
        label: 'Duration',
        icon: Icons.hourglass_bottom,
        options: [
          SettingOption('Bulb', 0),
          SettingOption('5 min', 300),
          SettingOption('15 min', 900),
          SettingOption('30 min', 1800),
          SettingOption('60 min', 3600),
        ],
        initial: 2,
      ),
      ModeSetting(
        id: S.interval,
        label: 'Interval',
        icon: Icons.av_timer,
        options: [
          SettingOption('0.5s', 0.5),
          SettingOption('1s', 1),
          SettingOption('2s', 2),
        ],
        initial: 1,
        help: 'Time between frames. Shorter gives smoother trails.',
      ),
      ModeSetting(
        id: S.threshold,
        label: 'Sky glow cut',
        icon: Icons.flare,
        options: [
          SettingOption('Off', 0),
          SettingOption('Low', 30),
          SettingOption('High', 60),
        ],
        initial: 1,
        help: 'Ignores faint sky glow so only stars draw trails.',
      ),
    ],
    tips: [
      'Go far from city lights on a clear, moonless night.',
      'Tripod is essential. Point at the pole star (north) for circular trails.',
      'Leave it running 15 minutes or more. The screen stays on; plug in a power bank.',
      'Phone sensors see only bright stars; longer runs give denser trails.',
    ],
  ),
  ShootMode(
    id: 'landscape_hdr',
    name: 'Landscape HDR',
    tagline: 'Bright sky and dark ground, both detailed',
    hint: 'Level the horizon, then hold still for the brackets.',
    icon: Icons.landscape,
    color: Color(0xFF43A047),
    kind: ModeKind.hdr,
    overlay: ModeOverlay.level,
    settings: [
      ModeSetting(
        id: S.bracket,
        label: 'Bracket',
        icon: Icons.exposure,
        options: [
          SettingOption('±1 EV', 0.15),
          SettingOption('±2 EV', 0.3),
          SettingOption('±3 EV', 0.45),
        ],
        initial: 1,
        help:
            'How much darker and brighter the extra shots are. Use more '
            'for sunsets and backlit scenes.',
      ),
      ModeSetting(
        id: S.shots,
        label: 'Shots',
        icon: Icons.filter_3,
        options: [SettingOption('3', 3), SettingOption('5', 5)],
      ),
    ],
    tips: [
      'Several photos are taken from dark to bright, then fused.',
      'Use a tripod, or hold very still for about 3 seconds.',
      'Great for sunsets, backlit scenes, and interiors with windows.',
      'Keep the level line green and put the horizon on a grid line, not the middle.',
    ],
  ),
  ShootMode(
    id: 'crowd_remover',
    name: 'Crowd Remover',
    tagline: 'Make tourists disappear from landmarks',
    hint: 'Tripod. Anyone who keeps moving will vanish.',
    icon: Icons.person_off,
    color: Color(0xFF00897B),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.median),
    analysisFps: 4,
    settings: [
      ModeSetting(
        id: S.duration,
        label: 'Duration',
        icon: Icons.hourglass_bottom,
        options: [
          SettingOption('10s', 10),
          SettingOption('20s', 20),
          SettingOption('30s', 30),
        ],
        initial: 1,
        help: 'Longer removes busier crowds. One frame is kept per interval.',
      ),
      ModeSetting(
        id: S.interval,
        label: 'Interval',
        icon: Icons.av_timer,
        options: [SettingOption('1s', 1), SettingOption('2s', 2)],
      ),
      _support,
    ],
    tips: [
      'Tripod strongly recommended.',
      'Anyone who keeps moving is removed; people standing still will stay.',
      'Works best when no spot is blocked for more than half the time.',
    ],
  ),
  ShootMode(
    id: 'echo',
    name: 'Motion Echo',
    tagline: 'Dancers, skaters and jumps leave ghost trails',
    hint: 'Camera still, subject moves across the frame.',
    icon: Icons.blur_on,
    color: Color(0xFFD81B60),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.echo),
    analysisFps: 15,
    settings: [
      ModeSetting(
        id: S.decay,
        label: 'Trail',
        icon: Icons.gesture,
        options: [
          SettingOption('Short', 0.7),
          SettingOption('Medium', 0.85),
          SettingOption('Long', 0.93),
        ],
        initial: 1,
        help: 'How long each ghost lingers before fading.',
      ),
      ModeSetting(
        id: S.interval,
        label: 'Ghosts',
        icon: Icons.copy_all,
        options: [
          SettingOption('Smooth', 0),
          SettingOption('Strobe', 0.2),
          SettingOption('Sparse', 0.4),
        ],
        help:
            'Smooth blends every frame. Strobe keeps separate copies, '
            'like a flash firing several times.',
      ),
      ModeSetting(
        id: S.duration,
        label: 'Length',
        icon: Icons.shutter_speed,
        options: [
          SettingOption('2s', 2),
          SettingOption('3s', 3),
          SettingOption('5s', 5),
          SettingOption('Bulb', 0),
        ],
        initial: 1,
      ),
    ],
    tips: [
      'Keep the camera still and let the subject move across the frame.',
      'A plain, darker background makes the echoes pop.',
      'Bright clothing on the subject works best.',
      'Strobe gives distinct copies: great for a jump or a skateboard trick.',
    ],
  ),
  ShootMode(
    id: 'slit_scan',
    name: 'Time Slice',
    tagline: 'Slit-scan: space becomes time, surreal shapes',
    hint: 'Only the coloured line is recorded, one slice per frame.',
    icon: Icons.view_week,
    color: Color(0xFF6D4C41),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.slitScan),
    analysisFps: 30,
    overlay: ModeOverlay.slitLine,
    settings: [
      ModeSetting(
        id: S.direction,
        label: 'Slit',
        icon: Icons.swap_horiz,
        options: [SettingOption('Vertical', 1), SettingOption('Horizontal', 0)],
        help:
            'Vertical builds the picture left to right; horizontal top to '
            'bottom.',
      ),
      ModeSetting(
        id: S.slit,
        label: 'Speed',
        icon: Icons.speed,
        options: [
          SettingOption('Slow', 2),
          SettingOption('Normal', 4),
          SettingOption('Fast', 8),
        ],
        initial: 1,
        help: 'Slow takes longer and stretches movement; fast squeezes it.',
      ),
    ],
    tips: [
      'Only the slit (coloured line) of each frame is used, placed side by side over time.',
      'Moving subjects past a still camera get stretched or squeezed (photo finish).',
      'Slowly pan the phone for warped panoramas, or turn your head for fun portraits.',
    ],
  ),
  ShootMode(
    id: 'pro_photo',
    name: 'Pro Photo',
    tagline: 'Grid, level, timer, exposure and zoom',
    hint: 'Tap to focus. Use the level for straight horizons.',
    icon: Icons.photo_camera,
    color: Color(0xFF546E7A),
    kind: ModeKind.photo,
    overlay: ModeOverlay.level,
    settings: [
      ModeSetting(
        id: S.aspect,
        label: 'Ratio',
        icon: Icons.aspect_ratio,
        options: [SettingOption('4:3', 0), SettingOption('16:9', 1)],
      ),
    ],
    tips: [
      'Rule of thirds: put the subject on a grid line intersection.',
      'Use the 3s or 10s timer with a tripod to avoid shake.',
      'Tap to focus; drag EV down to keep skies from blowing out.',
      'Golden hour (the hour after sunrise and before sunset) gives the warmest light.',
    ],
  ),
];

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

/// One "way to click": a recipe of capture settings plus advice on how to
/// get a great shot with it.
class ShootMode {
  const ShootMode({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    required this.kind,
    this.stack,
    this.analysisFps = 15,
    this.analysisWidth = 1280,
    this.autoStopFrames = 0,
    this.nightTone = false,
    this.tips = const [],
  });

  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color color;
  final ModeKind kind;
  final StackOptions? stack;
  final double analysisFps;

  /// Android only: width of frames requested from CameraX. iOS sends the
  /// session's native video size.
  final int analysisWidth;

  /// Capture stops by itself after this many frames (0 = user stops it).
  final int autoStopFrames;
  final bool nightTone;
  final List<String> tips;

  bool get isOpenEnded => autoStopFrames == 0;
}

const photoModes = <ShootMode>[
  ShootMode(
    id: 'light_painting',
    name: 'Light Painting',
    tagline: 'Draw with a torch, phone light or sparkler',
    icon: Icons.auto_fix_high,
    color: Color(0xFFFFB300),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten, lightenThreshold: 60),
    tips: [
      'Put the phone on a tripod or lean it on something solid. It must not move.',
      'Work in a dark room or outdoors at night. Only the moving light should be bright.',
      'Lower exposure (EV slider) until the background is nearly black.',
      'Press start, then walk into the frame and draw. Wear dark clothes so you stay invisible.',
      'Raise the "light threshold" if the background slowly brightens; lower it for faint lights.',
    ],
  ),
  ShootMode(
    id: 'light_trails',
    name: 'Light Trails',
    tagline: 'Car headlights and tail lights become ribbons',
    icon: Icons.route,
    color: Color(0xFFE53935),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten),
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
    icon: Icons.water,
    color: Color(0xFF039BE5),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.average, align: true),
    autoStopFrames: 90,
    tips: [
      'Works in daylight with no ND filter: the app averages many frames.',
      'Tripod gives the sharpest rocks; handheld works thanks to alignment.',
      'Moving water, waves and drifting clouds turn smooth. Still things stay sharp.',
      'More frames means silkier water. Stop early for some texture.',
    ],
  ),
  ShootMode(
    id: 'night',
    name: 'Night',
    tagline: 'Bright, clean photos in low light',
    icon: Icons.nightlight_round,
    color: Color(0xFF5E35B1),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.average, align: true),
    analysisFps: 20,
    analysisWidth: 1920,
    autoStopFrames: 24,
    nightTone: true,
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
    icon: Icons.star,
    color: Color(0xFF283593),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.lighten, lightenThreshold: 40),
    analysisFps: 2,
    analysisWidth: 1920,
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
    icon: Icons.landscape,
    color: Color(0xFF43A047),
    kind: ModeKind.hdr,
    tips: [
      'Three photos are taken at dark, normal and bright exposure, then fused.',
      'Use a tripod, or hold very still for about 3 seconds.',
      'Great for sunsets, backlit scenes, and interiors with windows.',
      'Use the rule-of-thirds grid: horizon on the top or bottom line, not the middle.',
    ],
  ),
  ShootMode(
    id: 'crowd_remover',
    name: 'Crowd Remover',
    tagline: 'Make tourists disappear from landmarks',
    icon: Icons.person_off,
    color: Color(0xFF00897B),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.median, align: true),
    analysisFps: 1,
    autoStopFrames: 15,
    tips: [
      'Tripod strongly recommended. Captures one frame per second for 15 seconds.',
      'Anyone who keeps moving is removed; people standing still will stay.',
      'Works best when no spot is blocked for more than half the time.',
    ],
  ),
  ShootMode(
    id: 'echo',
    name: 'Motion Echo',
    tagline: 'Dancers, skaters and jumps leave ghost trails',
    icon: Icons.blur_on,
    color: Color(0xFFD81B60),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.echo, echoDecay: 0.9),
    analysisFps: 12,
    autoStopFrames: 36,
    tips: [
      'Keep the camera still and let the subject move across the frame.',
      'A plain, darker background makes the echoes pop.',
      'Bright clothing on the subject works best.',
    ],
  ),
  ShootMode(
    id: 'slit_scan',
    name: 'Time Slice',
    tagline: 'Slit-scan: space becomes time, surreal shapes',
    icon: Icons.view_week,
    color: Color(0xFF6D4C41),
    kind: ModeKind.stack,
    stack: StackOptions(blend: StackBlend.slitScan, slitWidth: 4),
    analysisFps: 30,
    tips: [
      'Only the centre column of each frame is used, placed left to right over time.',
      'Moving subjects past a still camera get stretched or squeezed (photo finish).',
      'Slowly pan the phone for warped panoramas, or rotate your face for fun portraits.',
    ],
  ),
  ShootMode(
    id: 'pro_photo',
    name: 'Pro Photo',
    tagline: 'Grid, timer, exposure and zoom controls',
    icon: Icons.photo_camera,
    color: Color(0xFF546E7A),
    kind: ModeKind.photo,
    tips: [
      'Rule of thirds: put the subject on a grid line intersection.',
      'Use the 3s or 10s timer with a tripod to avoid shake.',
      'Tap to focus; drag EV down to keep skies from blowing out.',
      'Golden hour (the hour after sunrise and before sunset) gives the warmest light.',
    ],
  ),
];

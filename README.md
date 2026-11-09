# Creative Camera

A Flutter camera app for **Android and iPhone** with creative photo modes,
YouTube video presets and YouTube Live streaming.

## What it does

### Creative photo modes
| Mode | How it works |
| --- | --- |
| **Light Painting** | "Lighten" stacking: every pixel keeps the brightest value it has seen, so only the moving light is recorded while the dark scene stays put. A threshold slider stops the background from creeping brighter. |
| **Light Trails** | Same lighten stack, tuned for car headlights and tail lights at dusk. |
| **Silky Water** | Digital long exposure: frames are aligned and averaged, so water and clouds turn smooth in daylight without an ND filter. |
| **Night** | Burst of frames, each aligned to the first, averaged to remove noise, then brightened with a tone curve. |
| **Star Trails** | Slow lighten stack (2 frames/s) for long tripod runs under the night sky. |
| **Landscape HDR** | Three bracketed photos (dark, normal, bright) aligned and merged with Mertens exposure fusion in a Laplacian pyramid. |
| **Crowd Remover** | Median of 15 frames shot one second apart; people walking through disappear. |
| **Motion Echo** | Decaying multiple exposure: moving subjects leave fading ghost trails. |
| **Time Slice** | Slit-scan: the centre column of each frame is laid side by side, turning time into space. |
| **Pro Photo** | Rule-of-thirds grid, 3 s / 10 s timer, EV, zoom, flash. |

Every mode has a **How to shoot** sheet (lightbulb button) with practical photography advice.

### Video for YouTube
Presets for **Cooking** (4K, overhead tips, 5 s countdown), **YouTube 4K**, **Vlog** (front camera) and **Shorts/Reels** (vertical).
Recording supports pause/resume. Tap **Mark step** while recording; when you stop, you get
editable **YouTube chapter timestamps** to copy into your video description.

### YouTube Live
RTMP streaming to YouTube (or Facebook, Twitch, any RTMP server) at 480p, 720p or 1080p,
landscape or vertical, with an optional on-screen title, mic mute and camera switch.

## How it is built

- **[CamerAwesome](https://github.com/Apparence-io/CamerAwesome)** (MIT): camera preview, photo, video and the live frame stream used by the creative modes.
- **[HaishinKit](https://github.com/HaishinKit/HaishinKit.dart)** Flutter plugin (BSD-3): wraps HaishinKit.kt on Android and HaishinKit.swift on iOS for RTMP live streaming.
- Image processing (`lib/processing/`) is plain Dart running in a background isolate, so it works the same on both platforms and is covered by unit tests (`test/processing_test.dart`).

Ideas, not code, were taken from these projects:
- [PhotonCamera](https://github.com/bjzhou/PhotonCamera): multi-frame alignment and stacking for night shots. It is GPL-3.0, so none of its code is included, to keep this app's license your choice.
- [ExperimentalCapture](https://github.com/golanlevin/ExperimentalCapture): slit-scan, time displacement, light painting, echo.
- [SimpleRawCamera](https://github.com/danopdev/SimpleRawCamera): RAW capture. **Not yet implemented** (see Roadmap).

## Build and run

Requires Flutter 3.47 or newer.

```bash
flutter pub get
flutter test              # processing unit tests
flutter run               # on a connected phone
flutter build apk         # Android
flutter build ios         # iOS (open ios/Runner.xcworkspace in Xcode to sign)
```

Every push runs GitHub Actions (`.github/workflows/build.yml`), which tests the code and builds
an Android APK and an unsigned iOS app. Download them from the run's **Artifacts** section.
To install on an iPhone you need to sign the app with your Apple developer account in Xcode.

## Roadmap

- RAW (DNG) capture through a native Camera2 / AVCapturePhotoOutput channel.
- Full sensor resolution for stacking modes (currently the analysis stream: about 1280 to 1920 px wide).
- Manual shutter speed and ISO (needs native camera control beyond CamerAwesome).
- Timelapse and hyperlapse video.
- Streaming overlays: logo, live chat, scoreboard.

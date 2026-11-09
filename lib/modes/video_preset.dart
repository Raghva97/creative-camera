import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart';

/// A ready-made recording setup for a kind of YouTube content.
class VideoPreset {
  const VideoPreset({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    required this.quality,
    required this.bitrate,
    this.fps = 30,
    this.frontCamera = false,
    this.countdownSeconds = 3,
    this.chapters = true,
    this.tips = const [],
  });

  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color color;
  final VideoRecordingQuality quality;

  /// Android only, bits per second.
  final int bitrate;

  /// iOS only.
  final int fps;
  final bool frontCamera;
  final int countdownSeconds;

  /// Offer a "mark step" button that produces YouTube chapter timestamps.
  final bool chapters;
  final List<String> tips;

  VideoOptions get videoOptions => VideoOptions(
    enableAudio: true,
    quality: quality,
    android: AndroidVideoOptions(
      bitrate: bitrate,
      fallbackStrategy: QualityFallbackStrategy.lower,
    ),
    ios: CupertinoVideoOptions(fps: fps),
  );

  SensorPosition get sensorPosition =>
      frontCamera ? SensorPosition.front : SensorPosition.back;
}

const videoPresets = <VideoPreset>[
  VideoPreset(
    id: 'cooking',
    name: 'Cooking',
    tagline: 'Overhead recipe videos with step chapters',
    icon: Icons.restaurant,
    color: Color(0xFFF4511E),
    quality: VideoRecordingQuality.uhd,
    bitrate: 35000000,
    countdownSeconds: 5,
    tips: [
      'Mount the phone overhead (top-down) on an arm or tripod, about 60 cm above the counter.',
      'Light from a window at the side, never from behind the camera, to avoid your own shadow.',
      'Tap "Mark step" each time you start a new step. When you stop, you get YouTube chapter timestamps to paste into the description.',
      'Use the 5 second countdown so your hands are in position when recording starts.',
      'Clean the lens: kitchen grease makes video hazy.',
    ],
  ),
  VideoPreset(
    id: 'youtube_4k',
    name: 'YouTube 4K',
    tagline: 'Landscape 16:9 at the highest quality',
    icon: Icons.smart_display,
    color: Color(0xFFFF0000),
    quality: VideoRecordingQuality.uhd,
    bitrate: 40000000,
    tips: [
      'Hold the phone sideways for 16:9.',
      'Lock exposure by keeping the EV slider fixed while you move.',
      'Record room tone (10 seconds of silence) for easier audio editing.',
    ],
  ),
  VideoPreset(
    id: 'vlog',
    name: 'Vlog',
    tagline: 'Selfie camera, 1080p, talk to your audience',
    icon: Icons.record_voice_over,
    color: Color(0xFF8E24AA),
    quality: VideoRecordingQuality.fhd,
    bitrate: 16000000,
    frontCamera: true,
    tips: [
      'Hold the phone at arm\'s length, slightly above eye level.',
      'Face a window: soft light on your face, not behind you.',
      'Use chapters to mark topic changes for your description.',
    ],
  ),
  VideoPreset(
    id: 'shorts',
    name: 'Shorts / Reels',
    tagline: 'Vertical 9:16 for Shorts and Reels',
    icon: Icons.stay_current_portrait,
    color: Color(0xFF00ACC1),
    quality: VideoRecordingQuality.fhd,
    bitrate: 16000000,
    chapters: false,
    tips: [
      'Hold the phone upright for vertical 9:16.',
      'Hook the viewer in the first 2 seconds.',
      'Shorts can run up to 3 minutes, but under 60 seconds performs best; the timer turns red at 60.',
    ],
  ),
];

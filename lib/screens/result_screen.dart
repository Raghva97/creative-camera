import 'dart:io';

import 'package:flutter/material.dart';

/// Shows a finished picture.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.path,
    required this.savedToGallery,
    required this.title,
  });

  final String path;
  final bool savedToGallery;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(child: Image.file(File(path))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  savedToGallery ? Icons.check_circle : Icons.error_outline,
                  color: savedToGallery
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    savedToGallery
                        ? 'Saved to your gallery in the "Creative Camera" album.'
                        : 'Could not save to the gallery. Allow photo access in Settings.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Shoot again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

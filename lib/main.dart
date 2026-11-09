import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const CreativeCameraApp());
}

class CreativeCameraApp extends StatelessWidget {
  const CreativeCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Creative Camera',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
      ),
      theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

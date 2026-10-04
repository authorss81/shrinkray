import 'package:flutter/material.dart';

import 'rust/engine.dart';
import 'state/resize_controller.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const ShrinkRayApp());
}

/// The application.
///
/// The engine is created once here and handed to the controller, rather than the
/// controller creating its own. That is what lets a test inject a fake: the
/// constructor takes an engine and `runApp` is where the real one appears.
///
/// Every screen takes the controller as a parameter rather than reaching for a
/// provider. With one controller and one screen tree that is less machinery, and
/// a test can construct any screen without standing up a provider tree.
class ShrinkRayApp extends StatefulWidget {
  const ShrinkRayApp({super.key, this.engine});

  /// Overridden by tests. Null in the real app, where the controller builds the
  /// default engine.
  final PixelSmithEngine? engine;

  @override
  State<ShrinkRayApp> createState() => _ShrinkRayAppState();
}

class _ShrinkRayAppState extends State<ShrinkRayApp> {
  late final ResizeController _controller = ResizeController(
    engine: widget.engine,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShrinkRay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
import 'package:flutter/material.dart';

import 'rust/engine.dart';
import 'rust/models.dart';

/// ShrinkRay entry point.
///
/// This is a placeholder shell. The engine binding underneath it is real and
/// tested (`test/ffi_contract_test.dart`, `test/models_test.dart`); the UI
/// phases build on top of [PixelSmithEngine], they do not re-prove it.
void main() {
  runApp(const ShrinkRayApp());
}

class ShrinkRayApp extends StatelessWidget {
  const ShrinkRayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShrinkRay',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const EngineProbePage(),
    );
  }
}

/// Shows the engine version reported by the native library.
///
/// This page exists so the very first run proves the FFI boundary works
/// end to end. It is replaced by the real shell in a later UI phase.
class EngineProbePage extends StatefulWidget {
  const EngineProbePage({super.key});

  @override
  State<EngineProbePage> createState() => _EngineProbePageState();
}

class _EngineProbePageState extends State<EngineProbePage> {
  late final Future<Capabilities> _capabilities;

  @override
  void initState() {
    super.initState();
    _capabilities = PixelSmithEngine().version();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShrinkRay')),
      body: Center(
        child: FutureBuilder<Capabilities>(
          future: _capabilities,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Engine unreachable:\n${snapshot.error}',
                textAlign: TextAlign.center,
              );
            }
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final caps = snapshot.data!;
            return Text(
              'Engine ${caps.version}\n'
              'WebP lossy: ${caps.webpLossy}\n'
              'AVIF encode: ${caps.avifEncode}',
              textAlign: TextAlign.center,
            );
          },
        ),
      ),
    );
  }
}

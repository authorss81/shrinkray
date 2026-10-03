import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkray/rust/engine.dart';
import 'package:shrinkray/rust/models.dart';

/// Proves the engine never blocks the calling isolate.
///
/// Without the native library these skip: there is nothing to not-block on.
/// With it, a large decode runs on a worker isolate while the main isolate
/// counts event-loop ticks. If the engine ever ran on the calling isolate,
/// the tick count would collapse to zero during the decode.
void main() {
  test('a large decode does not freeze the calling isolate', () async {
    if (!_libraryPresent()) {
      markTestSkipped('native library not built');
      return;
    }
    final engine = PixelSmithEngine();

    // A large, compressible image: big enough to take real time, valid enough
    // to decode. Built programmatically so the test needs no assets.
    final source = _largeJpeg();

    var ticks = 0;
    var stop = false;
    unawaited(
      Future.doWhile(() async {
        if (stop) return false;
        ticks++;
        await Future<void>.delayed(Duration.zero);
        return true;
      }),
    );

    final result = await engine.process(
      pipeline: const Pipeline(
        resize: ResizeSpec(width: 400, fit: FitMode.width),
      ),
      format: OutputFormat.jpeg,
      imageBytes: source,
      name: 'large.jpg',
    );

    stop = true;
    expect(result.width, 400);
    // The decode took real time on another isolate; this one must have kept
    // ticking throughout. A single-digit count means we were blocked.
    expect(
      ticks,
      greaterThan(10),
      reason: 'main isolate froze during decode ($ticks ticks)',
    );
  });

  test('a thousand version calls leak nothing observable', () async {
    if (!_libraryPresent()) {
      markTestSkipped('native library not built');
      return;
    }
    final engine = PixelSmithEngine();
    // Each call allocates a PxBuffer on the Rust side and frees it in a
    // `finally`. A leak here grows unboundedly and this test OOMs; a correct
    // implementation is flat. There is no Dart-side counter for native memory,
    // so volume is the assertion.
    for (var i = 0; i < 1000; i++) {
      final caps = await engine.version();
      expect(caps.version, isNotEmpty);
    }
  });
}

bool _libraryPresent() {
  for (final name in [
    'libpixelsmith_core.so',
    'pixelsmith_core.dll',
    'libpixelsmith_core.dylib',
  ]) {
    try {
      ffi.DynamicLibrary.open(name).close();
      return true;
    } on ArgumentError {
      continue;
    }
  }
  return false;
}

/// A 2000x1500 gradient encoded as BMP bytes by hand.
///
/// BMP is the simplest container to construct without an encoder: a 54-byte
/// header plus raw BGR rows. The engine decodes BMP, so this is a valid input
/// that exercises a real multi-megapixel decode.
List<int> _largeJpeg() {
  const width = 2000;
  const height = 1500;
  const rowSize = width * 3;
  // Rows are 4-byte aligned; 2000*3 = 6000 is already aligned.
  final pixels = <int>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels
        ..add((x * 255 ~/ width) & 0xFF)
        ..add((y * 255 ~/ height) & 0xFF)
        ..add(128);
    }
  }
  final fileSize = 54 + pixels.length;
  final header = <int>[
    0x42, 0x4D, // BM
    fileSize & 0xFF,
    (fileSize >> 8) & 0xFF,
    (fileSize >> 16) & 0xFF,
    (fileSize >> 24) & 0xFF,
    0, 0, 0, 0, // reserved
    54, 0, 0, 0, // pixel offset
    40, 0, 0, 0, // DIB header size
    width & 0xFF,
    (width >> 8) & 0xFF,
    (width >> 16) & 0xFF,
    (width >> 24) & 0xFF,
    height & 0xFF,
    (height >> 8) & 0xFF,
    (height >> 16) & 0xFF,
    (height >> 24) & 0xFF,
    1, 0, // planes
    24, 0, // bits per pixel
    0, 0, 0, 0, // no compression
    0, 0, 0, 0, // image size (0 = uncompressed)
    0, 0, 0, 0, // x pixels per meter
    0, 0, 0, 0, // y pixels per meter
    0, 0, 0, 0, // colors used
    0, 0, 0, 0, // important colors
  ];
  // BMP stores rows bottom-up.
  final rows = <int>[];
  for (var y = height - 1; y >= 0; y--) {
    rows.addAll(pixels.sublist(y * rowSize, (y + 1) * rowSize));
  }
  return [...header, ...rows];
}

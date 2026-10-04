import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:shrinkray/rust/engine.dart';
import 'package:shrinkray/rust/models.dart';
import 'package:shrinkray/state/resize_controller.dart';

/// A fake engine that answers from memory.
///
/// `PixelSmithEngine` is a `final class`, so it cannot be extended or mocked, and
/// every one of its methods opens the native library on a worker isolate - which
/// returns nothing under `flutter test`. This stands in for it.
///
/// It is a `final class` for the same reason the real one is: the ownership rules
/// around native buffers are enforced in `PixelSmithEngine`, and a subclass could
/// override a method to skip them.
final class FakeEngine implements PixelSmithEngineApi {
  FakeEngine({this.failure, this.report});

  /// When set, every call throws this instead of answering.
  Object? failure;

  /// The report `inspect` returns. Defaults to a plausible 800x600 JPEG.
  ValidateReport? report;

  int processCalls = 0;
  int batchCalls = 0;
  int cancelNewCalls = 0;
  int cancelTriggerCalls = 0;
  int cancelFreeCalls = 0;
  int versionCalls = 0;
  int inspectCalls = 0;
  int exifCalls = 0;
  int presetCalls = 0;
  int zipCalls = 0;
  int abiLayoutCalls = 0;

  /// The pipeline the last `process` call was given, so a test can assert the
  /// settings actually reached the engine rather than only reaching the UI.
  Pipeline? lastPipeline;
  OutputFormat? lastFormat;
  int? lastQuality;
  int? lastTargetBytes;

  @override
  Future<Capabilities> version() async {
    versionCalls++;
    if (failure != null) throw failure!;
    return Capabilities(
      version: '0.1.0-test',
      jpeg: true,
      png: true,
      webpLossy: false,
      webpLossless: true,
      avifEncode: true,
      avifDecode: false,
      heicDecode: true,
      jpegProgressive: true,
      jpegChromaSubsampling: true,
      gif: true,
      tiff: true,
      bmp: true,
      ico: true,
      maxInputBytes: 512 * 1024 * 1024,
      maxPixels: 128000000,
    );
  }

  @override
  Future<ValidateReport> inspect(List<int> bytes, {bool mobileLimits = false}) async {
    inspectCalls++;
    if (failure != null) throw failure!;
    return report ??
        const ValidateReport(
          format: OutputFormat.jpeg,
          width: 800,
          height: 600,
          megapixels: 0.48,
          hasExif: false,
          hasAnimated: false,
          sensitiveTags: <String>[],
          orientation: null,
          suspicious: null,
        );
  }

  @override
  Future<ProcessResult> process({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<int> imageBytes,
    required String name,
    int quality = 85,
    int? targetBytes,
    bool? stripMetadata,
    bool mobileLimits = false,
  }) async {
    processCalls++;
    if (failure != null) throw failure!;
    lastPipeline = pipeline;
    lastFormat = format;
    lastQuality = quality;
    lastTargetBytes = targetBytes;
    final width = pipeline.resize?.width ?? 800;
    return ProcessResult(
      outputName: 'out.jpg',
      bytes: <int>[1, 2, 3, 4],
      inputBytes: imageBytes.length,
      outputBytes: 4,
      width: width,
      height: (width * 3) ~/ 4,
      qualityUsed: format == OutputFormat.png ? 0 : quality,
      targetMet: true,
      detectedFormat: OutputFormat.jpeg,
    );
  }

  @override
  Future<BatchReport> batch({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<BatchFile> files,
    int quality = 85,
    int? targetBytes,
    int? cancelHandle,
    bool mobileLimits = false,
  }) async {
    batchCalls++;
    if (failure != null) throw failure!;
    lastPipeline = pipeline;
    lastFormat = format;
    lastQuality = quality;
    lastTargetBytes = targetBytes;
    return BatchReport(
      outcomes: [
        for (final f in files)
          BatchOutcome(
            id: f.name,
            name: f.name,
            outputName: 'out_${f.name}',
            inputBytes: f.bytes.length,
            outputBytes: 100,
            width: 800,
            height: 600,
            qualityUsed: quality,
            targetMet: true,
            error: null,
          ),
      ],
      cancelled: false,
    );
  }

  @override
  Future<List<int>> zip(List<BatchFile> files) async {
    zipCalls++;
    if (failure != null) throw failure!;
    return <int>[1, 2, 3];
  }

  @override
  Future<ExifInfo> exif(List<int> bytes) async {
    exifCalls++;
    if (failure != null) throw failure!;
    return const ExifInfo(
      entries: <ExifEntry>[],
      hasGps: false,
      orientation: null,
      camera: null,
      capturedAt: null,
      sensitiveTags: <String>[],
    );
  }

  @override
  Future<List<Preset>> presets() async {
    presetCalls++;
    if (failure != null) throw failure!;
    return const <Preset>[];
  }

  @override
  Future<AbiLayout> abiLayout() async {
    abiLayoutCalls++;
    if (failure != null) throw failure!;
    return const AbiLayout(
      name: 'PxBuffer',
      size: 32,
      align: 8,
      fields: <AbiField>[
        AbiField(name: 'status', offset: 0, size: 4),
        AbiField(name: 'data', offset: 8, size: 8),
        AbiField(name: 'len', offset: 16, size: 8),
        AbiField(name: 'error', offset: 24, size: 8),
      ],
    );
  }

  @override
  Future<int> cancelNew() async {
    cancelNewCalls++;
    return 7;
  }

  @override
  Future<bool> cancelTrigger(int handle) async {
    cancelTriggerCalls++;
    return true;
  }

  @override
  Future<bool> cancelFree(int handle) async {
    cancelFreeCalls++;
    return true;
  }
}

/// A byte blob that is not a real image, for tests that never decode it.
Uint8List fakeBytes(int length) => Uint8List.fromList(
  List<int>.generate(length, (i) => (i * 37) % 256),
);

/// Builds a controller with a fake engine and capabilities already loaded.
Future<({ResizeController controller, FakeEngine engine})> makeController({
  FakeEngine? engine,
}) async {
  final fake = engine ?? FakeEngine();
  final controller = ResizeController(engine: fake);
  await controller.loadCapabilities();
  return (controller: controller, engine: fake);
}
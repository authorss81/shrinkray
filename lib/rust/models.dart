import 'dart:convert';

/// Output formats the engine can write.
///
/// Serialised lowercase to match `OutputFormat` in `core/src/format.rs`, which
/// carries `#[serde(rename_all = "lowercase")]`. A mismatch here is a silent
/// "bad request" from the engine, so `models_test.dart` round-trips every
/// value.
enum OutputFormat {
  jpeg,
  png,
  webp,
  gif,
  tiff,
  bmp,
  ico,
  avif;

  String toJson() => name;

  static OutputFormat fromJson(String value) =>
      OutputFormat.values.byName(value.toLowerCase());
}

/// How the source image fills the requested box.
///
/// Matches `FitMode` in `core/src/pipeline.rs` (`snake_case`).
enum FitMode {
  contain,
  cover,
  fill,
  width,
  height;

  String toJson() => name;

  static FitMode fromJson(String value) => FitMode.values.byName(value);
}

/// Resampling kernel. Matches `ResampleFilter` in `core/src/pipeline.rs`.
enum ResampleFilter {
  lanczos3,
  catmullRom,
  triangle,
  nearest,
  box;

  String toJson() => switch (this) {
    ResampleFilter.lanczos3 => 'lanczos3',
    ResampleFilter.catmullRom => 'catmull_rom',
    ResampleFilter.triangle => 'triangle',
    ResampleFilter.nearest => 'nearest',
    ResampleFilter.box => 'box',
  };

  static ResampleFilter fromJson(String value) => switch (value) {
    'lanczos3' => ResampleFilter.lanczos3,
    'catmull_rom' => ResampleFilter.catmullRom,
    'triangle' => ResampleFilter.triangle,
    'nearest' => ResampleFilter.nearest,
    'box' => ResampleFilter.box,
    _ => throw ArgumentError('unknown resample filter: $value'),
  };
}

/// EXIF orientation correction. Matches `Orientation` in `core/src/pipeline.rs`.
enum Orientation {
  normal,
  mirrorHorizontal,
  rotate180,
  mirrorVertical,
  mirrorHorizontalRotate270,
  rotate90,
  mirrorHorizontalRotate90,
  rotate270;

  String toJson() => switch (this) {
    Orientation.normal => 'normal',
    Orientation.mirrorHorizontal => 'mirror_horizontal',
    Orientation.rotate180 => 'rotate180',
    Orientation.mirrorVertical => 'mirror_vertical',
    Orientation.mirrorHorizontalRotate270 => 'mirror_horizontal_rotate270',
    Orientation.rotate90 => 'rotate90',
    Orientation.mirrorHorizontalRotate90 => 'mirror_horizontal_rotate90',
    Orientation.rotate270 => 'rotate270',
  };
}

/// Centre crop in source pixel coordinates. Applied before resize.
final class CropSpec {
  const CropSpec({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static CropSpec fromJson(Map<String, Object?> json) => CropSpec(
    x: (json['x'] as num).toInt(),
    y: (json['y'] as num).toInt(),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
  );
}

final class ResizeSpec {
  const ResizeSpec({
    this.width,
    this.height,
    this.fit = FitMode.contain,
    this.filter = ResampleFilter.lanczos3,
    this.noUpscale = true,
  });

  final int? width;
  final int? height;
  final FitMode fit;
  final ResampleFilter filter;

  /// Refuse to enlarge. Respected by default: upscaling a photo past its native
  /// resolution adds bytes and zero detail.
  final bool noUpscale;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'fit': fit.toJson(),
    'filter': filter.toJson(),
    'no_upscale': noUpscale,
  };
}

/// The complete, ordered transform: crop, then orient, then resize.
///
/// The order is fixed engine-side. This class mirrors it so the UI cannot
/// construct an impossible pipeline.
final class Pipeline {
  const Pipeline({
    this.crop,
    this.orientation,
    this.resize,
    this.stripMetadata = true,
  });

  final CropSpec? crop;
  final Orientation? orientation;
  final ResizeSpec? resize;

  /// Strip metadata by re-encoding. Defaults to true because phone photos carry
  /// GPS coordinates, and keeping them silently would publish that.
  final bool stripMetadata;

  Map<String, Object?> toJson() => {
    'crop': crop?.toJson(),
    'orientation': orientation?.toJson(),
    'resize': resize?.toJson(),
    'strip_metadata': stripMetadata,
  };
}

/// What the engine learned from a file before trusting it.
///
/// Mirrors `ValidateReport` in `core/src/validate.rs`.
final class ValidateReport {
  const ValidateReport({
    required this.format,
    required this.width,
    required this.height,
    required this.megapixels,
    required this.hasExif,
    required this.hasAnimated,
    required this.sensitiveTags,
    required this.orientation,
    required this.suspicious,
  });

  final OutputFormat format;
  final int width;
  final int height;
  final double megapixels;
  final bool hasExif;
  final bool hasAnimated;
  final List<String> sensitiveTags;
  final int? orientation;

  /// Human-readable warning, or null when the file looks ordinary.
  final String? suspicious;

  static ValidateReport fromJson(Map<String, Object?> json) => ValidateReport(
    format: OutputFormat.fromJson(json['format'] as String),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
    megapixels: (json['megapixels'] as num).toDouble(),
    hasExif: json['has_exif'] as bool,
    hasAnimated: json['has_animated'] as bool,
    sensitiveTags: (json['sensitive_tags'] as List).cast<String>(),
    orientation: (json['orientation'] as num?)?.toInt(),
    suspicious: json['suspicious'] as String?,
  );
}

/// A single EXIF tag.
final class ExifEntry {
  const ExifEntry({required this.tag, required this.value});

  final String tag;
  final String value;

  static ExifEntry fromJson(Map<String, Object?> json) =>
      ExifEntry(tag: json['tag'] as String, value: json['value'] as String);
}

/// Full EXIF read. Mirrors `ExifInfo` in `core/src/exif.rs`.
final class ExifInfo {
  const ExifInfo({
    required this.entries,
    required this.hasGps,
    required this.orientation,
    required this.camera,
    required this.capturedAt,
    required this.sensitiveTags,
  });

  final List<ExifEntry> entries;
  final bool hasGps;
  final int? orientation;
  final String? camera;
  final String? capturedAt;
  final List<String> sensitiveTags;

  static ExifInfo fromJson(Map<String, Object?> json) => ExifInfo(
    entries: (json['entries'] as List)
        .map((e) => ExifEntry.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    hasGps: json['has_gps'] as bool,
    orientation: (json['orientation'] as num?)?.toInt(),
    camera: json['camera'] as String?,
    capturedAt: json['captured_at'] as String?,
    sensitiveTags: (json['sensitive_tags'] as List).cast<String>(),
  );
}

/// One built-in preset. Mirrors `Preset` in `core/src/presets.rs`.
///
/// The engine serialises presets out but never reads them back — `Preset` holds
/// `&'static str`, which cannot be deserialised from a runtime buffer — so this
/// is an owned mirror, not a round-trip type. `toJson` is intentionally absent.
final class Preset {
  const Preset({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.format,
  });

  final String id;
  final String label;
  final int width;
  final int? height;
  final OutputFormat format;

  static Preset fromJson(Map<String, Object?> json) => Preset(
    id: json['id'] as String,
    label: json['label'] as String,
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num?)?.toInt(),
    format: OutputFormat.fromJson(json['format'] as String),
  );
}

/// The result of processing one image. Mirrors `ProcessResponse` in
/// `core/src/ffi.rs`.
final class ProcessResult {
  const ProcessResult({
    required this.outputName,
    required this.bytes,
    required this.inputBytes,
    required this.outputBytes,
    required this.width,
    required this.height,
    required this.qualityUsed,
    required this.targetMet,
    required this.detectedFormat,
  });

  final String outputName;
  final List<int> bytes;
  final int inputBytes;
  final int outputBytes;
  final int width;
  final int height;

  /// Quality actually used. Differs from the request when a byte target forced
  /// a search.
  final int qualityUsed;

  /// False when the byte target could not be met.
  final bool targetMet;
  final OutputFormat detectedFormat;

  double get savedPercent =>
      inputBytes == 0 ? 0.0 : (1.0 - outputBytes / inputBytes) * 100.0;

  static ProcessResult fromJson(Map<String, Object?> json) => ProcessResult(
    outputName: json['output_name'] as String,
    bytes: (json['bytes'] as List).map((b) => (b as num).toInt()).toList(),
    inputBytes: (json['input_bytes'] as num).toInt(),
    outputBytes: (json['output_bytes'] as num).toInt(),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
    qualityUsed: (json['quality_used'] as num).toInt(),
    targetMet: json['target_met'] as bool,
    detectedFormat: OutputFormat.fromJson(json['detected_format'] as String),
  );
}

/// Per-file outcome in a batch. Mirrors `Outcome` in `core/src/worker.rs`.
final class BatchOutcome {
  const BatchOutcome({
    required this.id,
    required this.name,
    required this.outputName,
    required this.inputBytes,
    required this.outputBytes,
    required this.width,
    required this.height,
    required this.qualityUsed,
    required this.targetMet,
    required this.error,
  });

  final String id;
  final String name;
  final String outputName;
  final int inputBytes;
  final int outputBytes;
  final int width;
  final int height;
  final int qualityUsed;
  final bool targetMet;

  /// Set when this file failed. Every failure carries a reason.
  final String? error;

  bool get ok => error == null;

  static BatchOutcome fromJson(Map<String, Object?> json) => BatchOutcome(
    id: json['id'] as String,
    name: json['name'] as String,
    outputName: json['output_name'] as String,
    inputBytes: (json['input_bytes'] as num).toInt(),
    outputBytes: (json['output_bytes'] as num).toInt(),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
    qualityUsed: (json['quality_used'] as num).toInt(),
    targetMet: json['target_met'] as bool,
    error: json['error'] as String?,
  );
}

/// A batch report. Mirrors `BatchReport` in `core/src/worker.rs`.
final class BatchReport {
  const BatchReport({required this.outcomes, required this.cancelled});

  final List<BatchOutcome> outcomes;
  final bool cancelled;

  int get succeeded => outcomes.where((o) => o.ok).length;
  int get failed => outcomes.where((o) => !o.ok).length;

  static BatchReport fromJson(Map<String, Object?> json) => BatchReport(
    outcomes: (json['outcomes'] as List)
        .map((o) => BatchOutcome.fromJson((o as Map).cast<String, Object?>()))
        .toList(),
    cancelled: json['cancelled'] as bool,
  );
}

/// Engine capabilities. Mirrors `Capabilities` in `core/src/lib.rs`.
final class Capabilities {
  const Capabilities({
    required this.version,
    required this.webpLossy,
    required this.avifEncode,
    required this.maxInputBytes,
    required this.maxPixels,
  });

  final String version;
  final bool webpLossy;
  final bool avifEncode;
  final int maxInputBytes;
  final int maxPixels;

  static Capabilities fromJson(Map<String, Object?> json) {
    final caps = (json['capabilities'] as Map).cast<String, Object?>();
    return Capabilities(
      version: json['version'] as String,
      webpLossy: caps['webp_lossy'] as bool,
      avifEncode: caps['avif_encode'] as bool,
      maxInputBytes: (caps['max_input_bytes'] as num).toInt(),
      maxPixels: (caps['max_pixels'] as num).toInt(),
    );
  }
}

/// Builds the JSON envelopes the engine expects.
///
/// Kept next to the models so a request shape and its builder cannot drift.
abstract final class Requests {
  static String process({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<int> imageBytes,
    required String name,
    int quality = 85,
    int? targetBytes,
    bool? stripMetadata,
    bool mobileLimits = false,
  }) => jsonEncode({
    'pipeline': pipeline.toJson(),
    'format': format.toJson(),
    'quality': quality,
    'target': targetBytes,
    'name': name,
    'data_base64': base64Encode(imageBytes),
    'strip_metadata': stripMetadata,
    'mobile_limits': mobileLimits,
  });

  static String batch({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<BatchFile> files,
    int quality = 85,
    int? targetBytes,
    int? cancelHandle,
    bool mobileLimits = false,
  }) => jsonEncode({
    ...pipeline.toJson(),
    'format': format.toJson(),
    'quality': quality,
    'target': targetBytes,
    'mobile_limits': mobileLimits,
    'cancel': cancelHandle,
    'files': [
      for (final f in files)
        {
          'name': f.name,
          // A JSON number array costs up to four characters per byte. Base64
          // would be better here too, but the engine's BatchFile takes a byte
          // array, so this matches the contract rather than improving it.
          'bytes': f.bytes,
        },
    ],
  });

  static String zip(List<BatchFile> files) => jsonEncode({
    'files': [
      for (final f in files) {'name': f.name, 'bytes': f.bytes},
    ],
  });
}

final class BatchFile {
  const BatchFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// The engine's own report of a struct's memory layout, from the library that
/// actually got loaded.
///
/// Read by `ffi_contract_test.dart` and compared against [PxBuffer]'s Dart
/// declaration. It exists so a mismatch between the app's bindings and the engine
/// binary on disk is a failed test rather than corrupted memory during a decode:
/// `PxBuffer` is passed by value, so a wrong offset reads a pointer out of the
/// wrong place and hands it to `free`.
final class AbiLayout {
  const AbiLayout({
    required this.name,
    required this.size,
    required this.align,
    required this.fields,
  });

  final String name;

  /// Total size in bytes.
  final int size;

  /// Required alignment in bytes.
  final int align;

  final List<AbiField> fields;

  /// The offset of [field], or null when the engine does not report it.
  ///
  /// Named lookup rather than positional access, so a field the engine adds later
  /// does not shift every index in the caller.
  int? offsetOf(String field) {
    for (final f in fields) {
      if (f.name == field) return f.offset;
    }
    return null;
  }

  factory AbiLayout.fromJson(Map<String, Object?> json) => AbiLayout(
    name: json['name'] as String? ?? 'PxBuffer',
    size: (json['size'] as num?)?.toInt() ?? 0,
    align: (json['align'] as num?)?.toInt() ?? 0,
    fields: ((json['fields'] as List?) ?? const [])
        .map((e) => AbiField.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
  );

  @override
  String toString() =>
      'AbiLayout($name, size $size, align $align, ${fields.length} fields)';
}

/// One field within an [AbiLayout].
final class AbiField {
  const AbiField({
    required this.name,
    required this.offset,
    required this.size,
  });

  final String name;
  final int offset;
  final int size;

  factory AbiField.fromJson(Map<String, Object?> json) => AbiField(
    name: json['name'] as String? ?? '?',
    offset: (json['offset'] as num?)?.toInt() ?? -1,
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() => '$name@$offset+$size';
}

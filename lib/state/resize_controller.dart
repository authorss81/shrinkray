import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rust/engine.dart';
import '../rust/models.dart';

/// One image the user has chosen, and everything the engine has told us about it.
///
/// The bytes are held rather than a path because the engine takes bytes, and a
/// path would mean a second read at export time — on Android the content URI
/// grant can expire, and a file that was readable when picked is not guaranteed
/// to be readable later.
final class PickedImage {
  PickedImage({
    required this.id,
    required this.name,
    required this.bytes,
    this.report,
    this.error,
  });

  /// Stable identity for selection state. A content URI is not unique enough:
  /// a picker can hand back the same path twice in one session.
  final String id;

  final String name;
  final Uint8List bytes;

  /// The engine's header report, once inspection has completed.
  final ValidateReport? report;

  /// Why inspection failed, if it did.
  ///
  /// A separate field rather than a null [report], because "this file is not an
  /// image" and "we have not looked yet" are different states and the UI shows
  /// them differently.
  final String? error;

  int get width => report?.width ?? 0;
  int get height => report?.height ?? 0;
  bool get inspected => report != null || error != null;
  bool get failed => error != null;

  /// Whether the engine found metadata worth telling the user about.
  bool get hasExif => report?.hasExif ?? false;

  /// Whether the engine found GPS. This is the reason the app exists in part, so
  /// it is surfaced rather than silently stripped.
  bool get hasSensitiveTags => (report?.sensitiveTags.isNotEmpty) ?? false;

  PickedImage copyWith({ValidateReport? report, String? error}) => PickedImage(
    id: id,
    name: name,
    bytes: bytes,
    report: report ?? this.report,
    error: error,
  );
}

/// The state of one export, as the UI needs to show it.
///
/// Deliberately not the engine's [ProcessResult]: progress and failure happen
/// before there is a result, and a screen that can only render a completed result
/// cannot show a user that anything is happening.
enum ExportPhase { idle, running, done, failed, cancelled }

/// Everything the user can change about an export, in one place.
///
/// Held by a [ChangeNotifier] rather than in widget state because the cropper,
/// the settings sheet and the export button all read and write the same values.
/// Spreading them across three `State` objects is how a slider ends up showing
/// 85 while the export uses 90.
///
/// The engine call itself is injected as [engine] so widget tests can drive the
/// whole flow without loading a native library.
final class ResizeController extends ChangeNotifier {
  ResizeController({PixelSmithEngine? engine})
    : _engine = engine ?? PixelSmithEngine();

  final PixelSmithEngine _engine;

  final List<PickedImage> _images = <PickedImage>[];
  final Set<String> _selected = <String>{};

  // --- Export settings -------------------------------------------------------

  OutputFormat _format = OutputFormat.jpeg;
  int _quality = 85;
  int? _targetBytes;
  int? _maxWidth;
  int? _maxHeight;
  FitMode _fit = FitMode.contain;
  ResampleFilter _filter = ResampleFilter.lanczos3;
  bool _noUpscale = true;
  bool _stripMetadata = true;
  /// Per-image crop, keyed by image id. A crop is meaningless for a batch where
  /// the images differ, so this only applies to a single-image export.
  final Map<String, CropSpec> _crops = <String, CropSpec>{};

  // --- Transient state -------------------------------------------------------

  Capabilities? _capabilities;
  ExportPhase _phase = ExportPhase.idle;
  String? _statusLine;
  ProcessResult? _lastResult;
  BatchReport? _lastBatch;
  String? _error;
  double _progress = 0;

  // --- Reads -----------------------------------------------------------------

  List<PickedImage> get images => List.unmodifiable(_images);
  Set<String> get selectedIds => Set.unmodifiable(_selected);
  OutputFormat get format => _format;
  int get quality => _quality;
  int? get targetBytes => _targetBytes;
  int? get maxWidth => _maxWidth;
  int? get maxHeight => _maxHeight;
  FitMode get fit => _fit;
  ResampleFilter get filter => _filter;
  bool get noUpscale => _noUpscale;
  bool get stripMetadata => _stripMetadata;
  Capabilities? get capabilities => _capabilities;
  ExportPhase get phase => _phase;
  String? get statusLine => _statusLine;
  ProcessResult? get lastResult => _lastResult;
  BatchReport? get lastBatch => _lastBatch;
  String? get error => _error;
  double get progress => _progress;

  bool get isBusy => _phase == ExportPhase.running;
  bool get hasImages => _images.isNotEmpty;
  bool get hasSelection => _selected.isNotEmpty;
  bool get isBatch => _selected.length > 1;

  /// Selected images, in the order they were picked.
  ///
  /// Order is stable because a batch whose output order depends on a `Set`
  /// iteration is a batch whose ZIP entries move between runs.
  List<PickedImage> get selectedImages => _images
      .where((i) => _selected.contains(i.id))
      .toList(growable: false);

  CropSpec? cropFor(String id) => _crops[id];

  // --- Capabilities ----------------------------------------------------------

  /// Load the engine's capability list.
  ///
  /// Called once at startup and before the format picker is shown, because a
  /// format this build cannot write has to be visibly unavailable rather than
  /// selectable and then refused (hard rule 10).
  Future<void> loadCapabilities() async {
    try {
      _capabilities = await _engine.version();
      _error = null;
    } catch (e) {
      _error = 'The image engine could not be loaded: $e';
      _phase = ExportPhase.failed;
    }
    notifyListeners();
  }

  /// Whether this build can write [candidate].
  ///
  /// Answers from [Capabilities] rather than from a hard-coded list, so the
  /// engine and the UI cannot disagree about what is possible.
  bool canWrite(OutputFormat candidate) {
    // Checked before the capabilities, because it does not depend on the build:
    // there is no HEVC encoder in this engine at all, so no feature flag makes
    // HEIC writable.
    if (!candidate.isWritable) return false;

    final caps = _capabilities;
    if (caps == null) {
      // Before capabilities load, claim nothing. A wrong "yes" here produces an
      // export that fails at the last step, after the user waited for it.
      return false;
    }
    return switch (candidate) {
      OutputFormat.jpeg => caps.jpeg,
      OutputFormat.png => caps.png,
      OutputFormat.webp => caps.webpLossy || caps.webpLossless,
      OutputFormat.avif => caps.avifEncode,
      // Encodable in principle, but the UI offers only what this build reports,
      // and these are left off the menu rather than offered and refused.
      OutputFormat.gif ||
      OutputFormat.tiff ||
      OutputFormat.bmp ||
      OutputFormat.ico => false,
      OutputFormat.heic || OutputFormat.heif => false,
    };
  }

  /// Whether [candidate] responds to the quality slider.
  ///
  /// A property of the format, so it does not depend on capabilities loading.
  bool qualityAppliesTo(OutputFormat candidate) => candidate.hasQuality;

  // --- Adding images ---------------------------------------------------------

  /// Add already-loaded images, then inspect them.
  ///
  /// Inspection is per-file and failures are recorded rather than thrown: one
  /// unreadable file in a selection of 200 must not discard the other 199.
  Future<void> addImages(
    List<({String name, Uint8List bytes})> incoming, {
    bool mobileLimits = false,
  }) async {
    for (final file in incoming) {
      final id = '${file.name}#${file.bytes.length}#${_images.length}';
      _images.add(
        PickedImage(id: id, name: file.name, bytes: file.bytes),
      );
      _selected.add(id);
    }
    notifyListeners();

    for (final image in _images) {
      if (image.inspected) continue;
      await _inspect(image, mobileLimits: mobileLimits);
    }
    notifyListeners();
  }

  Future<void> _inspect(
    PickedImage image, {
    required bool mobileLimits,
  }) async {
    final index = _images.indexWhere((i) => i.id == image.id);
    if (index < 0) return; // removed while we were awaiting
    try {
      final report = await _engine.inspect(image.bytes, mobileLimits: mobileLimits);
      final latest = _images[index];
      if (latest.id != image.id) return;
      _images[index] = latest.copyWith(report: report);
    } catch (e) {
      final latest = _images[index];
      if (latest.id != image.id) return;
      _images[index] = latest.copyWith(error: '$e');
    }
    notifyListeners();
  }

  void removeImage(String id) {
    _images.removeWhere((i) => i.id == id);
    _selected.remove(id);
    _crops.remove(id);
    notifyListeners();
  }

  void clearImages() {
    _images.clear();
    _selected.clear();
    _crops.clear();
    _phase = ExportPhase.idle;
    _error = null;
    _statusLine = null;
    _lastResult = null;
    _lastBatch = null;
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(_images.where((i) => !i.failed).map((i) => i.id));
    notifyListeners();
  }

  void deselectAll() {
    _selected.clear();
    notifyListeners();
  }

  // --- Setting changes -------------------------------------------------------

  void setFormat(OutputFormat value) {
    if (_format == value) return;
    _format = value;
    // A byte target only means something for a format with a quality setting,
    // so turning it on for a lossless format would show a control that cannot
    // work.
    if (!qualityAppliesTo(value)) {
      _targetBytes = null;
    }
    notifyListeners();
  }

  void setQuality(int value) {
    final clamped = value.clamp(1, 100);
    if (_quality == clamped) return;
    _quality = clamped;
    notifyListeners();
  }

  void setTargetBytes(int? value) {
    final next = (value == null || value <= 0) ? null : value;
    if (_targetBytes == next) return;
    _targetBytes = next;
    notifyListeners();
  }

  /// Set the width bound. Null means "do not constrain this axis".
  void setMaxWidth(int? value) {
    final next = (value == null || value <= 0) ? null : value;
    if (_maxWidth == next) return;
    _maxWidth = next;
    notifyListeners();
  }

  void setMaxHeight(int? value) {
    final next = (value == null || value <= 0) ? null : value;
    if (_maxHeight == next) return;
    _maxHeight = next;
    notifyListeners();
  }

  void setFit(FitMode value) {
    if (_fit == value) return;
    _fit = value;
    notifyListeners();
  }

  void setFilter(ResampleFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setNoUpscale(bool value) {
    if (_noUpscale == value) return;
    _noUpscale = value;
    notifyListeners();
  }

  void setStripMetadata(bool value) {
    if (_stripMetadata == value) return;
    _stripMetadata = value;
    notifyListeners();
  }

  void setCrop(String id, CropSpec? crop) {
    if (crop == null) {
      _crops.remove(id);
    } else {
      _crops[id] = crop;
    }
    notifyListeners();
  }

  // --- Export ----------------------------------------------------------------

  /// The pipeline the engine will be asked to run.
  ///
  /// Built in one place so the preview the user sees and the export they get
  /// cannot come from different constructions.
  Pipeline pipelineFor(PickedImage image) => Pipeline(
    crop: _crops[image.id],
    resize: ResizeSpec(
      width: _maxWidth,
      height: _maxHeight,
      fit: _fit,
      filter: _filter,
      noUpscale: _noUpscale,
    ),
    stripMetadata: _stripMetadata,
  );

  /// A human-readable summary of what the export will do.
  ///
  /// Shown before the user commits, because "resize to 1920 wide, JPEG q85, no
  /// metadata" is a decision and "Export" is not.
  String get summary {
    final parts = <String>[];
    final crop = _crops.length == 1 ? _crops.values.first : null;
    if (crop != null) {
      parts.add('crop ${crop.width}x${crop.height}');
    }
    if (_maxWidth != null || _maxHeight != null) {
      final w = _maxWidth?.toString() ?? 'auto';
      final h = _maxHeight?.toString() ?? 'auto';
      parts.add('fit $w x $h (${_fit.name})');
    } else {
      parts.add('original size');
    }
    if (_noUpscale) parts.add('no upscale');
    parts.add(_format.name.toUpperCase());
    if (qualityAppliesTo(_format)) {
      parts.add('q$_quality');
    }
    if (_targetBytes != null) {
      parts.add('under ${_formatBytes(_targetBytes!)}');
    }
    parts.add(_stripMetadata ? 'metadata removed' : 'metadata kept');
    return parts.join(' · ');
  }

  /// Run the export over the current selection.
  ///
  /// Uses the batch path for more than one image and the single path for one,
  /// because the single path returns the bytes directly and the batch path
  /// returns a report. Both go through the same settings, so a batch is not a
  /// subtly different operation.
  Future<void> export({
    bool mobileLimits = false,
    int? cancelHandle,
  }) async {
    final chosen = selectedImages.where((i) => !i.failed).toList(growable: false);
    if (chosen.isEmpty || isBusy) return;

    _phase = ExportPhase.running;
    _error = null;
    _statusLine = chosen.length == 1
        ? 'Resizing ${chosen.first.name}…'
        : 'Resizing ${chosen.length} images…';
    _progress = 0;
    _lastResult = null;
    _lastBatch = null;
    notifyListeners();

    try {
      if (chosen.length == 1) {
        final image = chosen.first;
        final result = await _engine.process(
          pipeline: pipelineFor(image),
          format: _format,
          imageBytes: image.bytes,
          name: image.name,
          quality: _quality,
          targetBytes: _targetBytes,
          stripMetadata: _stripMetadata,
          mobileLimits: mobileLimits,
        );
        _lastResult = result;
        _phase = ExportPhase.done;
        _statusLine = result.targetMet || _targetBytes == null
            ? 'Saved ${result.outputName}'
            : 'Saved ${result.outputName} — could not reach the size limit';
      } else {
        final report = await _engine.batch(
          pipeline: pipelineFor(chosen.first),
          format: _format,
          files: [
            for (final i in chosen)
              BatchFile(name: i.name, bytes: i.bytes),
          ],
          quality: _quality,
          targetBytes: _targetBytes,
          cancelHandle: cancelHandle,
          mobileLimits: mobileLimits,
        );
        _lastBatch = report;
        final failed = report.outcomes.where((o) => o.error != null).length;
        _phase = report.cancelled ? ExportPhase.cancelled : ExportPhase.done;
        _statusLine = report.cancelled
            ? 'Cancelled after ${report.outcomes.length - failed} of ${chosen.length}'
            : failed == 0
            ? 'Resized ${report.outcomes.length} images'
            : 'Resized ${report.outcomes.length - failed}, $failed failed';
      }
      _progress = 1;
    } catch (e) {
      _error = '$e';
      _phase = ExportPhase.failed;
      _statusLine = 'Export failed';
    }
    notifyListeners();
  }

  /// Reset the transient export state so the screen returns to idle.
  void acknowledgeExport() {
    _phase = ExportPhase.idle;
    _statusLine = null;
    _error = null;
    _progress = 0;
    _lastResult = null;
    _lastBatch = null;
    notifyListeners();
  }
}

/// Formats a byte count the way a person reads it.
///
/// Binary units, because that is what a file manager shows next to the file and
/// two different number systems in one app is a support question.
String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 100 || unit == 0
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}
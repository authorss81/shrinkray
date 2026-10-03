import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'errors.dart';
import 'models.dart';

/// Loads the native engine library for the current platform.
///
/// The library name differs per platform because each one has its own
/// convention, and getting it wrong is a startup crash rather than an error:
/// - Android: `libpixelsmith_core.so`, bundled per ABI by `cargo-ndk`.
/// - iOS/macOS: statically linked; `DynamicLibrary.process()`.
/// - Windows: `pixelsmith_core.dll`, sitting next to the EXE.
/// - Linux: `libpixelsmith_core.so`, sitting next to the binary.
ffi.DynamicLibrary loadEngineLibrary() {
  if (ffi.Abi.current() == ffi.Abi.androidArm64 ||
      ffi.Abi.current() == ffi.Abi.androidArm ||
      ffi.Abi.current() == ffi.Abi.androidX64) {
    return ffi.DynamicLibrary.open('libpixelsmith_core.so');
  }
  if (ffi.Abi.current() == ffi.Abi.iosArm64 ||
      ffi.Abi.current() == ffi.Abi.macosArm64 ||
      ffi.Abi.current() == ffi.Abi.macosX64) {
    return ffi.DynamicLibrary.process();
  }
  if (ffi.Abi.current() == ffi.Abi.windowsX64) {
    return ffi.DynamicLibrary.open('pixelsmith_core.dll');
  }
  return ffi.DynamicLibrary.open('libpixelsmith_core.so');
}

/// The safe wrapper around every `px_*` entry point.
///
/// Rules, enforced here rather than trusted to callers:
/// - Every buffer the engine returns is owned here and freed in a `finally`.
///   A raw pointer never escapes.
/// - Every call runs on a worker isolate, so a two-second decode cannot drop a
///   frame. `Isolate.run` only accepts static entry points — a closure
///   capturing instance state throws at spawn time — so each operation builds
///   its request on the calling isolate and hands a plain string across. The
///   request JSON is cheap; the decode is not, which is exactly the split a
///   worker isolate wants.
/// - Failures become typed exceptions carrying the engine's message, never a
///   null, never a crash.
final class PixelSmithEngine {
  /// Engine version and capabilities. Use as a smoke test that the app linked
  /// the library it expected rather than a stale copy.
  Future<Capabilities> version() => Isolate.run(() => _versionStatic());

  /// Inspect a file's header without decoding pixels. Rejects a hostile file
  /// before a pixel buffer is allocated.
  Future<ValidateReport> inspect(List<int> bytes) =>
      Isolate.run(() => _inspectStatic(bytes));

  /// Full EXIF read.
  Future<ExifInfo> exif(List<int> bytes) =>
      Isolate.run(() => _exifStatic(bytes));

  /// The preset catalogue.
  Future<List<Preset>> presets() => Isolate.run(() => _presetsStatic());

  /// Process one image.
  Future<ProcessResult> process({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<int> imageBytes,
    required String name,
    int quality = 85,
    int? targetBytes,
    bool? stripMetadata,
    bool mobileLimits = false,
  }) {
    final request = Requests.process(
      pipeline: pipeline,
      format: format,
      imageBytes: imageBytes,
      name: name,
      quality: quality,
      targetBytes: targetBytes,
      stripMetadata: stripMetadata,
      mobileLimits: mobileLimits,
    );
    return Isolate.run(() => _processStatic(request));
  }

  /// Run a batch. Always returns a report, never throws for per-file failures;
  /// one unreadable file must not discard the other 199.
  Future<BatchReport> batch({
    required Pipeline pipeline,
    required OutputFormat format,
    required List<BatchFile> files,
    int quality = 85,
    int? targetBytes,
    int? cancelHandle,
    bool mobileLimits = false,
  }) {
    final request = Requests.batch(
      pipeline: pipeline,
      format: format,
      files: files,
      quality: quality,
      targetBytes: targetBytes,
      cancelHandle: cancelHandle,
      mobileLimits: mobileLimits,
    );
    return Isolate.run(() => _batchStatic(request));
  }

  /// Build a ZIP from already-processed outputs.
  Future<List<int>> zip(List<BatchFile> files) {
    final request = Requests.zip(files);
    return Isolate.run(() => _zipStatic(request));
  }

  /// Create a cancellation token. Returns 0 on failure.
  Future<int> cancelNew() => Isolate.run(() => _cancelNewStatic());

  /// Flip a cancellation token.
  Future<bool> cancelTrigger(int handle) =>
      Isolate.run(() => _cancelTriggerStatic(handle));

  /// Drop a cancellation token.
  Future<bool> cancelFree(int handle) =>
      Isolate.run(() => _cancelFreeStatic(handle));
}

// ---------------------------------------------------------------------------
// Static isolate entry points. Each opens its own library handle because
// `DynamicLibrary` is not sendable across isolates. Only plain data
// (strings, ints, byte lists) crosses the boundary.
// ---------------------------------------------------------------------------

Capabilities _versionStatic() {
  final px = PxBindings(loadEngineLibrary());
  return Capabilities.fromJson(_takeJson(px, px.version()));
}

ValidateReport _inspectStatic(List<int> bytes) {
  final px = PxBindings(loadEngineLibrary());
  final ptr = _copyToNative(bytes);
  try {
    return ValidateReport.fromJson(
      _takeJson(px, px.inspect(ptr, bytes.length)),
    );
  } finally {
    _freeNative(ptr);
  }
}

ExifInfo _exifStatic(List<int> bytes) {
  final px = PxBindings(loadEngineLibrary());
  final ptr = _copyToNative(bytes);
  try {
    return ExifInfo.fromJson(_takeJson(px, px.exif(ptr, bytes.length)));
  } finally {
    _freeNative(ptr);
  }
}

List<Preset> _presetsStatic() {
  final px = PxBindings(loadEngineLibrary());
  final list = _takeJsonList(px, px.presets());
  return list
      .map((e) => Preset.fromJson((e as Map).cast<String, Object?>()))
      .toList();
}

ProcessResult _processStatic(String request) {
  final px = PxBindings(loadEngineLibrary());
  final ptr = _copyToNative(utf8.encode(request));
  try {
    return ProcessResult.fromJson(
      _takeJson(px, px.process(ptr, request.length)),
    );
  } finally {
    _freeNative(ptr);
  }
}

BatchReport _batchStatic(String request) {
  final px = PxBindings(loadEngineLibrary());
  final ptr = _copyToNative(utf8.encode(request));
  try {
    return BatchReport.fromJson(_takeJson(px, px.batch(ptr, request.length)));
  } finally {
    _freeNative(ptr);
  }
}

List<int> _zipStatic(String request) {
  final px = PxBindings(loadEngineLibrary());
  final ptr = _copyToNative(utf8.encode(request));
  try {
    final buffer = px.zip(ptr, request.length);
    try {
      if (buffer.status != PxStatus.ok) {
        throw EngineProcessingException(_readError(buffer));
      }
      return buffer.data.asTypedList(buffer.len).toList();
    } finally {
      px.bufferFree(buffer);
    }
  } finally {
    _freeNative(ptr);
  }
}

int _cancelNewStatic() => PxBindings(loadEngineLibrary()).cancelNew();

bool _cancelTriggerStatic(int handle) =>
    PxBindings(loadEngineLibrary()).cancelTrigger(handle);

bool _cancelFreeStatic(int handle) =>
    PxBindings(loadEngineLibrary()).cancelFree(handle);

/// Interprets a returned buffer: parses the payload as JSON on success, frees
/// the buffer either way, and throws on failure.
Map<String, Object?> _takeJson(PxBindings px, PxBuffer buffer) {
  final decoded = _takeDecoded(px, buffer);
  return (decoded as Map).cast<String, Object?>();
}

/// Same, for endpoints that return a bare JSON array (`px_presets`).
List<Object?> _takeJsonList(PxBindings px, PxBuffer buffer) {
  final decoded = _takeDecoded(px, buffer);
  return (decoded as List).cast<Object?>();
}

Object? _takeDecoded(PxBindings px, PxBuffer buffer) {
  try {
    final status = buffer.status;
    final message = _readError(buffer);
    final List<int> data = buffer.data == ffi.nullptr
        ? const []
        : buffer.data.asTypedList(buffer.len).toList();
    if (status == PxStatus.ok) {
      return jsonDecode(utf8.decode(data));
    }
    if (status == PxStatus.invalidArgument) {
      throw EngineContractException(
        message.isEmpty ? 'engine rejected the call' : message,
      );
    }
    throw EngineProcessingException(
      message.isEmpty ? 'engine failed without explanation' : message,
    );
  } finally {
    px.bufferFree(buffer);
  }
}

String _readError(PxBuffer buffer) =>
    buffer.error == ffi.nullptr ? '' : buffer.error.cast<Utf8>().toDartString();

/// Copies bytes into native memory. The caller must free with [_freeNative].
ffi.Pointer<ffi.Uint8> _copyToNative(List<int> bytes) {
  final ptr = calloc<ffi.Uint8>(bytes.length);
  ptr.asTypedList(bytes.length).setAll(0, bytes);
  return ptr;
}

void _freeNative(ffi.Pointer<ffi.Uint8> ptr) => calloc.free(ptr);

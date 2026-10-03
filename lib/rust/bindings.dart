import 'dart:ffi' as ffi;

/// The owned result struct returned by every `px_*` function.
///
/// Layout must match `PxBuffer` in `core/src/ffi.rs` exactly:
/// ```c
/// struct PxBuffer { uint32_t status; uint8_t *data; size_t len; char *error; };
/// ```
/// On 64-bit targets that is 4 + 4 pad + 8 + 8 + 8 = 32 bytes. A mismatch here
/// is silent memory corruption, so `ffi_contract_test.dart` asserts the offsets
/// and the total size.
final class PxBuffer extends ffi.Struct {
  @ffi.Uint32()
  external int status;

  external ffi.Pointer<ffi.Uint8> data;

  @ffi.Size()
  external int len;

  external ffi.Pointer<ffi.Char> error;
}

/// Status codes. Must match `PxStatus` in `core/src/ffi.rs`.
abstract final class PxStatus {
  static const int ok = 0;
  static const int error = 1;

  /// The boundary was used incorrectly: null pointer, bad handle, a length that
  /// disagrees with the buffer. Never returned for ordinary input problems,
  /// only for caller bugs.
  static const int invalidArgument = 2;
}

/// Raw `dart:ffi` declarations for every `px_*` entry point.
///
/// Nothing in this file is safe to call directly: buffers must be freed exactly
/// once, and freeing twice is only safe because the Rust side no-ops on unknown
/// pointers. Use [PixelSmithEngine] instead, which owns every buffer it
/// receives and frees it in a `finally`.
final class PxBindings {
  PxBindings(this._lib);

  final ffi.DynamicLibrary _lib;

  late final _pxVersion = _lib
      .lookupFunction<PxBuffer Function(), PxBuffer Function()>('px_version');
  late final _pxBufferFree = _lib
      .lookupFunction<ffi.Void Function(PxBuffer), void Function(PxBuffer)>(
        'px_buffer_free',
      );
  late final _pxStringFree = _lib
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Char>),
        void Function(ffi.Pointer<ffi.Char>)
      >('px_string_free');
  late final _pxInspect = _lib
      .lookupFunction<
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, int)
      >('px_inspect');
  late final _pxExif = _lib
      .lookupFunction<
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, int)
      >('px_exif');
  late final _pxPresets = _lib
      .lookupFunction<PxBuffer Function(), PxBuffer Function()>('px_presets');
  late final _pxProcess = _lib
      .lookupFunction<
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, int)
      >('px_process');
  late final _pxBatch = _lib
      .lookupFunction<
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, int)
      >('px_batch');
  late final _pxZip = _lib
      .lookupFunction<
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
        PxBuffer Function(ffi.Pointer<ffi.Uint8>, int)
      >('px_zip');
  late final _pxCancelNew = _lib
      .lookupFunction<ffi.Uint64 Function(), int Function()>('px_cancel_new');
  late final _pxCancelTrigger = _lib
      .lookupFunction<ffi.Bool Function(ffi.Uint64), bool Function(int)>(
        'px_cancel_trigger',
      );
  late final _pxCancelFree = _lib
      .lookupFunction<ffi.Bool Function(ffi.Uint64), bool Function(int)>(
        'px_cancel_free',
      );
  late final _pxSelftestError = _lib
      .lookupFunction<PxBuffer Function(), PxBuffer Function()>(
        'px_selftest_error',
      );
  late final _pxSelftestPanic = _lib
      .lookupFunction<PxBuffer Function(), PxBuffer Function()>(
        'px_selftest_panic',
      );

  PxBuffer version() => _pxVersion();
  void bufferFree(PxBuffer b) => _pxBufferFree(b);
  void stringFree(ffi.Pointer<ffi.Char> s) => _pxStringFree(s);
  PxBuffer inspect(ffi.Pointer<ffi.Uint8> p, int len) => _pxInspect(p, len);
  PxBuffer exif(ffi.Pointer<ffi.Uint8> p, int len) => _pxExif(p, len);
  PxBuffer presets() => _pxPresets();
  PxBuffer process(ffi.Pointer<ffi.Uint8> p, int len) => _pxProcess(p, len);
  PxBuffer batch(ffi.Pointer<ffi.Uint8> p, int len) => _pxBatch(p, len);
  PxBuffer zip(ffi.Pointer<ffi.Uint8> p, int len) => _pxZip(p, len);
  int cancelNew() => _pxCancelNew();
  bool cancelTrigger(int h) => _pxCancelTrigger(h);
  bool cancelFree(int h) => _pxCancelFree(h);
  PxBuffer selftestError() => _pxSelftestError();
  PxBuffer selftestPanic() => _pxSelftestPanic();
}

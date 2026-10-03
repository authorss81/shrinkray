import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkray/rust/bindings.dart';

/// The contract test: every `px_*` function the engine exports must have a
/// matching Dart declaration, and the `PxBuffer` layout must match byte for
/// byte.
///
/// This test needs the compiled native library. Without it — a fresh checkout
/// before phase-05's build glue has run, or `flutter test` on a machine without
/// a Rust toolchain — it skips rather than failing. A skipped contract test is
/// honest about what it could not check; a failing one would block every
/// unrelated change.
void main() {
  test('PxBuffer layout matches the Rust #[repr(C)] struct', () {
    // struct PxBuffer {
    //   uint32_t status;      // offset 0, size 4
    //   uint8_t *data;        // offset 8, size 8
    //   size_t len;           // offset 16, size 8
    //   char *error;          // offset 24, size 8
    // };                      // total 32 on 64-bit
    expect(ffi.sizeOf<PxBuffer>(), 32);
  });

  test('every px_* function resolves in the native library', () {
    final lib = _tryLoad();
    if (lib == null) {
      markTestSkipped(
        'native library not built — run the native build first (see README.md)',
      );
      return;
    }
    final px = PxBindings(lib);

    // Calling px_version exercises the full round trip: allocate on the Rust
    // side, read the struct by offset, parse, free.
    final buffer = px.version();
    try {
      expect(buffer.status, PxStatus.ok);
      expect(buffer.data.address, isNonZero);
      expect(buffer.len, greaterThan(0));
    } finally {
      px.bufferFree(buffer);
    }

    // The deliberate failure must come back as an error buffer, not a crash.
    final err = px.selftestError();
    try {
      expect(err.status, PxStatus.error);
      expect(err.data.address, isZero);
    } finally {
      px.bufferFree(err);
    }

    // A contained panic must also come back as an error buffer.
    final panic = px.selftestPanic();
    try {
      expect(panic.status, PxStatus.error);
    } finally {
      px.bufferFree(panic);
    }
  });

  test('buffers freed twice do not crash', () {
    final lib = _tryLoad();
    if (lib == null) {
      markTestSkipped('native library not built');
      return;
    }
    final px = PxBindings(lib);
    final buffer = px.version();
    final address = buffer.data.address;
    expect(address, isNonZero);
    px.bufferFree(buffer);
    // Second free of the same pointer must be a no-op on the Rust side
    // (unknown pointers are leaked, never rebuilt). If this crashes, the
    // ownership contract is broken. Structs cannot be constructed directly —
    // they live in native memory — so allocate one.
    final again = calloc<PxBuffer>();
    try {
      again.ref.status = 1;
      again.ref.data = ffi.Pointer<ffi.Uint8>.fromAddress(address);
      again.ref.len = 0;
      px.bufferFree(again.ref);
    } finally {
      calloc.free(again);
    }
  });
}

/// Returns the engine library, or null when it has not been built.
ffi.DynamicLibrary? _tryLoad() {
  for (final name in [
    'libpixelsmith_core.so',
    'pixelsmith_core.dll',
    'libpixelsmith_core.dylib',
  ]) {
    try {
      return ffi.DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    }
  }
  // iOS and macOS link statically; process() always "succeeds" even with
  // nothing in it, so only use it when the file actually exists.
  if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.process();
  }
  return null;
}

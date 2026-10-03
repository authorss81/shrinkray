# ShrinkRay

A local-first image resizer. Flutter UI over the
[PixelSmith](https://github.com/authorss81/pixelsmith) Rust engine.

**It never uploads anything, because the engine has no network capability to
upload with.** No HTTP, TLS, socket or DNS crate in the dependency tree — check
it yourself with `cargo tree` in the engine checkout.

## Status

Scaffolding plus the complete FFI binding layer. The UI phases build the
interface on top of `lib/rust/`; they do not re-prove the boundary.

| Layer | State |
| --- | --- |
| `lib/rust/bindings.dart` | Raw `dart:ffi` declarations for every `px_*` function |
| `lib/rust/models.dart` | JSON request/response mirrors, serialised to match the engine's serde conventions |
| `lib/rust/errors.dart` | One exception type per engine status |
| `lib/rust/engine.dart` | Safe wrapper: owns every buffer, frees in `finally`, runs on a worker isolate |
| `test/models_test.dart` | Enum serialisation, request envelopes, boundary math |
| `test/ffi_contract_test.dart` | Layout assertion + every entry point, skipped when the library is not built |

## Building

### The engine

```bash
# From a checkout next to pixelsmith:
bash native/build-engine.sh --release

# Or against an explicit engine checkout:
bash native/build-engine.sh --release --engine-dir /path/to/pixelsmith
```

Requires a Rust toolchain. Android cross-compiles need `cargo-ndk` (the script
installs it); plain `cargo build --target aarch64-linux-android` fails at link
time with no linker, which is what the script exists to avoid.

### The app

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

`flutter test` passes with or without the native library: the contract test
skips gracefully when nothing is built, and says so.

### Release artefacts

`.github/workflows/build.yml` builds a debug-signed APK and a Windows release
bundle on every push, and asserts the APK contains `classes.dex` plus
`lib/*/libpixelsmith_core.so` — an APK without its native library opens fine
and crashes on first tap. Signed releases are cut by hand; see the PixelSmith
`phase-16` prompt for the checklist.

## The contract

The engine speaks JSON over a C ABI. The rules, enforced in `lib/rust/`:

- Every buffer the engine returns is owned by `PixelSmithEngine` and freed in a
  `finally`. A raw pointer never escapes.
- Every call runs on a worker isolate. A two-second decode cannot drop a frame.
- `PxBuffer` (`status: u32, data: *u8, len: usize, error: *c_char`) is 32 bytes
  on 64-bit. `ffi_contract_test.dart` asserts the size; a mismatch is silent
  memory corruption.
- Enum wire values match the engine's serde derives exactly: `OutputFormat` is
  lowercase, `FitMode`/`ResampleFilter`/`Orientation` are snake_case.
  `catmullRom` serialises as `catmull_rom` — sending camelCase is a silent "bad
  request".
- Images travel base64-encoded inside the request envelope. A JSON number array
  would cost up to four characters per byte.

## Licence

MIT OR Apache-2.0, matching the engine.

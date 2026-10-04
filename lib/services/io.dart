import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// A file the user chose, already read into memory.
typedef PickedFile = ({String name, Uint8List bytes});

/// Why a pick failed, in terms a user can act on.
class PickFailure implements Exception {
  const PickFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens the system file picker and reads the chosen files.
///
/// An interface rather than a direct `FilePicker` call so the widget tests can
/// drive picking without a platform channel, which returns nothing under
/// `flutter test` and would leave every test unable to reach the screen it is
/// supposed to be checking.
abstract interface class ImageSource {
  Future<List<PickedFile>> pickImages();
}

/// The real implementation, over `file_picker`.
class PlatformImageSource implements ImageSource {
  const PlatformImageSource();

  /// Extensions offered in the picker dialog.
  ///
  /// Matches what the engine can decode rather than everything the OS knows
  /// about, so a user is not invited to pick a PDF.
  static const List<String> supportedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'tif',
    'tiff',
    'bmp',
    'ico',
    'avif',
    'heic',
    'heif',
  ];

  @override
  Future<List<PickedFile>> pickImages() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
        // Multi-select: a folder of holiday photos is the case the batch path
        // exists for. A single pick is still one tap fewer on the far side.
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      throw PickFailure('The file picker could not be opened: $e');
    }

    if (result == null || result.files.isEmpty) {
      // The user cancelled. Not an error: returning empty lets the caller treat
      // "cancelled" and "picked nothing" identically, which is what both mean.
      return const <PickedFile>[];
    }

    final picked = <PickedFile>[];
    final skipped = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        // `withData: true` should always populate this. A null here means the file
        // was larger than the platform would hand over, and reporting it is
        // better than silently exporting nothing for it.
        skipped.add(file.name);
        continue;
      }
      picked.add((name: file.name, bytes: bytes));
    }

    if (picked.isEmpty && skipped.isNotEmpty) {
      throw PickFailure(
        'Could not read ${skipped.length} file(s), starting with '
        '"${skipped.first}". They may be too large for the picker to hand over.',
      );
    }
    return picked;
  }
}

/// Where an exported file goes.
enum ExportDestination {
  /// The platform's documents or pictures directory.
  appStorage,

  /// The system share sheet, so the user chooses where it goes.
  shareSheet,
}

/// Writes finished exports somewhere the user can find.
abstract interface class ExportWriter {
  /// Save [bytes] under [fileName]. Returns a line describing where it went.
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required ExportDestination destination,
  });
}

/// The real implementation.
///
/// Uses `path_provider` rather than a hard-coded path: on Android the app's own
/// directory is not visible in a gallery app without a MediaStore entry, and on
/// desktop the downloads folder is not the documents folder. Asking the platform
/// is the only version of this that is correct on both.
class PlatformExportWriter implements ExportWriter {
  const PlatformExportWriter();

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required ExportDestination destination,
  }) async {
    switch (destination) {
      case ExportDestination.shareSheet:
        // Deferred to the caller: sharing needs a BuildContext for the share
        // sheet on some platforms, so it is not done behind this interface's
        // back. Reported honestly rather than silently written to storage.
        throw const PickFailure(
          'Sharing is handled by the UI layer, which needs a screen context.',
        );
      case ExportDestination.appStorage:
        final directory = await _targetDirectory();
        final file = await _write(directory, fileName, bytes);
        return 'Saved to $file';
    }
  }

  Future<String> _write(
    String directory,
    String fileName,
    Uint8List bytes,
  ) async {
    final file = File('$directory${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> _targetDirectory() async {
    // Pictures on Android, documents elsewhere. `getApplicationDocumentsDirectory`
    // exists on every platform we ship, and `getDownloadsDirectory` is not
    // available on all of them, so it is not used here.
    final support = await getApplicationSupportDirectory();
    final output = Directory(
      '${support.path}${Platform.pathSeparator}exports',
    );
    if (!await output.exists()) {
      await output.create(recursive: true);
    }
    return output.path;
  }
}
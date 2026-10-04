import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/io.dart';
import '../state/resize_controller.dart';
import 'crop_screen.dart';
import 'settings_sheet.dart';

/// The main screen: what is selected, and what will happen to it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ResizeController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImageSource _source = const PlatformImageSource();
  bool _picking = false;
  String? _ioError;

  ResizeController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    if (_controller.capabilities == null) {
      _controller.loadCapabilities();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _ioError = null;
    });
    try {
      final files = await _source.pickImages();
      if (files.isNotEmpty) {
        await _controller.addImages(files);
      }
    } on PickFailure catch (e) {
      if (mounted) setState(() => _ioError = e.message);
    } catch (e) {
      if (mounted) setState(() => _ioError = 'Could not open the images: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _export() async {
    await _controller.export();
    if (!mounted) return;
    final controller = _controller;
    if (controller.phase == ExportPhase.done && controller.lastResult != null) {
      await _saveSingle(controller.lastResult!);
    } else if (controller.phase == ExportPhase.done &&
        controller.lastBatch != null) {
      await _saveBatch(controller.lastBatch!);
    }
  }

  Future<void> _saveSingle(dynamic result) async {
    final fileName = result.outputName as String;
    final bytes = Uint8List.fromList(result.bytes as List<int>);
    await _writeAndReport(fileName, bytes);
  }

  Future<void> _saveBatch(dynamic report) async {
    final outcomes = (report.outcomes as List)
        .where((o) => o.error == null)
        .toList(growable: false);
    if (outcomes.isEmpty) return;
    for (final outcome in outcomes) {
      await _writeAndReport(outcome.outputName as String, Uint8List.fromList(outcome.bytes as List<int>));
    }
  }

  Future<void> _writeAndReport(String fileName, Uint8List bytes) async {
    const writer = PlatformExportWriter();
    try {
      final where = await writer.save(
        fileName: fileName,
        bytes: bytes,
        destination: ExportDestination.appStorage,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(where)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _openCrop(PickedImage image) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CropScreen(controller: _controller, image: image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShrinkRay'),
        actions: [
          if (controller.hasImages)
            IconButton(
              tooltip: 'Select all',
              onPressed: controller.selectAll,
              icon: const Icon(Icons.select_all),
            ),
          if (controller.hasImages)
            IconButton(
              tooltip: 'Clear',
              onPressed: controller.clearImages,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_ioError != null)
            _ErrorBanner(
              message: _ioError!,
              onDismiss: () => setState(() => _ioError = null),
            ),
          Expanded(
            child: controller.hasImages
                ? _ImageGrid(
                    controller: controller,
                    onCrop: _openCrop,
                  )
                : _EmptyState(picking: _picking, onPick: _pick),
          ),
          if (controller.hasImages) _StatusBar(controller: controller),
        ],
      ),
      floatingActionButton: controller.hasImages
          ? FloatingActionButton.extended(
              onPressed: controller.isBusy ? null : _export,
              icon: controller.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: Text(
                controller.isBatch
                    ? 'Resize ${controller.selectedIds.length}'
                    : 'Resize',
              ),
            )
          : null,
      bottomNavigationBar: controller.hasImages
          ? _ActionBar(controller: controller, onExport: _export)
          : null,
    );
  }
}

/// The persistent bar: what the export will do, and the settings that change it.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller, required this.onExport});

  final ResizeController controller;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              controller.summary,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showSettingsSheet(context, controller),
                    icon: const Icon(Icons.tune),
                    label: const Text('Settings'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.isBusy ? null : onExport,
                    icon: const Icon(Icons.download),
                    label: const Text('Export'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.picking, required this.onPick});

  final bool picking;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No images yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Photos stay on this device. Nothing is uploaded.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: picking ? null : onPick,
            icon: picking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(picking ? 'Opening…' : 'Choose images'),
          ),
        ],
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.controller, required this.onCrop});

  final ResizeController controller;
  final Future<void> Function(PickedImage) onCrop;

  @override
  Widget build(BuildContext context) {
    final images = controller.images;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        return _ImageCard(
          image: image,
          selected: controller.selectedIds.contains(image.id),
          hasCrop: controller.cropFor(image.id) != null,
          onTap: () => controller.toggleSelection(image.id),
          onCrop: image.inspected && !image.failed
              ? () => onCrop(image)
              : null,
          onRemove: () => controller.removeImage(image.id),
        );
      },
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.selected,
    required this.hasCrop,
    required this.onTap,
    required this.onCrop,
    required this.onRemove,
  });

  final PickedImage image;
  final bool selected;
  final bool hasCrop;
  final VoidCallback onTap;
  final VoidCallback? onCrop;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // The selection ring is the only thing distinguishing a selected tile, so
        // it has to survive a theme that flattens surfaces.
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.failed)
                    ColoredBox(
                      color: scheme.errorContainer,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    )
                  else
                    Image.memory(
                      image.bytes,
                      fit: BoxFit.cover,
                      // A corrupt file must show the engine's message, not a
                      // framework exception the user cannot read.
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: scheme.errorContainer,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: scheme.primary,
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  if (hasCrop)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _Badge(
                        icon: Icons.crop,
                        background: scheme.secondaryContainer,
                        foreground: scheme.onSecondaryContainer,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitleFor(image),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: image.failed ? scheme.error : scheme.outline,
                    ),
                  ),
                  if (onCrop != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onCrop,
                        icon: const Icon(Icons.crop, size: 16),
                        label: const Text('Crop'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(PickedImage image) {
    if (image.failed) return image.error ?? 'Could not read';
    if (!image.inspected) return 'Reading…';
    final report = image.report!;
    final size = '${report.width}x${report.height}';
    if (report.hasExif) {
      return '$size · has EXIF';
    }
    return size;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 14, color: foreground),
    );
  }
}

/// Progress and the engine's own words about what happened.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = controller.error ?? controller.statusLine;
    if (message == null && !controller.isBusy) {
      return const SizedBox.shrink();
    }
    final isError = controller.error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (controller.isBusy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: isError ? scheme.onErrorContainer : scheme.primary,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isError ? scheme.onErrorContainer : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/models.dart';
import '../state/resize_controller.dart';

/// Opens the settings sheet over [controller].
Future<void> showSettingsSheet(
  BuildContext context,
  ResizeController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SettingsSheet(controller: controller),
  );
}

/// Size, format, quality and metadata.
///
/// Every control here writes to the controller and the controller is what the
/// export reads, so there is no second copy of the settings to fall out of sync.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    final caps = controller.capabilities;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            if (caps == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Reading what this build can write…',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),

            _Section(
              title: 'Output format',
              subtitle: caps == null
                  ? null
                  : 'Engine ${caps.version}',
              child: _FormatPicker(controller: controller),
            ),

            _Section(
              title: 'Size',
              subtitle: controller.maxWidth == null &&
                      controller.maxHeight == null
                  ? 'Images keep their original dimensions'
                  : null,
              child: _SizeControls(controller: controller),
            ),

            _Section(
              title: 'Quality',
              subtitle: controller.qualityAppliesTo(controller.format)
                  ? 'Higher is larger and clearer'
                  : 'Not used by ${controller.format.name.toUpperCase()} — '
                        'this format is lossless',
              child: controller.qualityAppliesTo(controller.format)
                  ? _QualityControls(controller: controller)
                  : const SizedBox.shrink(),
            ),

            _Section(
              title: 'Size limit',
              subtitle: controller.targetBytes == null
                  ? 'No ceiling'
                  : 'The engine lowers quality until the file fits',
              child: _TargetBytesControls(controller: controller),
            ),

            _Section(
              title: 'Privacy',
              child: _MetadataControls(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({required this.controller});

  final ResizeController controller;

  /// Formats worth showing. Everything else is read-only in this engine or is not
  /// offered because the build cannot produce it.
  static const List<OutputFormatOption> _options = [
    OutputFormatOption('jpeg', 'JPEG', 'Best for photos'),
    OutputFormatOption('png', 'PNG', 'Lossless, large files'),
    OutputFormatOption('webp', 'WebP', 'Smaller than JPEG'),
    OutputFormatOption('avif', 'AVIF', 'Smallest, slow to encode'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _options)
          _FormatChip(
            option: option,
            enabled: _canWrite(option.name),
            selected: option.name == controller.format.name,
            onTap: () => controller.setFormat(_toFormat(option.name)),
          ),
      ],
    );
  }

  bool _canWrite(String name) {
    final format = _toFormat(name);
    return controller.canWrite(format);
  }

  static OutputFormat _toFormat(String name) {
    for (final f in OutputFormat.values) {
      if (f.name == name) return f;
    }
    // Unreachable: every name in `_options` is a real enum member, and the list
    // is a const. Throwing beats a silent default.
    throw ArgumentError('no such format: $name');
  }
}

/// One entry in the format list, named rather than typed so the const list above
/// stays readable.
class OutputFormatOption {
  const OutputFormatOption(this.name, this.label, this.blurb);

  final String name;
  final String label;
  final String blurb;
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.option,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final OutputFormatOption option;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      // The blurb is the reason a format is greyed out, so it has to be
      // reachable rather than only visible to someone who guesses.
      message: enabled ? option.blurb : 'This build cannot write ${option.label}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  // A disabled control must not look selectable.
                  color: enabled ? null : scheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              if (!enabled) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.block,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.38),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeControls extends StatefulWidget {
  const _SizeControls({required this.controller});

  final ResizeController controller;

  @override
  State<_SizeControls> createState() => _SizeControlsState();
}

class _SizeControlsState extends State<_SizeControls> {
  late final TextEditingController _width = TextEditingController(
    text: widget.controller.maxWidth?.toString() ?? '',
  );
  late final TextEditingController _height = TextEditingController(
    text: widget.controller.maxHeight?.toString() ?? '',
  );

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  /// Common long-edge targets, which is how people actually think about it.
  static const List<({String label, int? longEdge})> _presets = [
    (label: 'Original', longEdge: null),
    (label: '4K', longEdge: 3840),
    (label: '2K', longEdge: 2560),
    (label: '1080p', longEdge: 1920),
    (label: '720p', longEdge: 1280),
    (label: 'Web', longEdge: 1200),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              ChoiceChip(
                label: Text(preset.label),
                selected: _matchesPreset(preset.longEdge),
                onSelected: (_) => _applyPreset(preset.longEdge),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _width,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Max width',
                  hintText: 'auto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => controller.setMaxWidth(int.tryParse(value)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _height,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Max height',
                  hintText: 'auto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => controller.setMaxHeight(int.tryParse(value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Fit', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in FitMode.values)
              ChoiceChip(
                label: Text(_fitLabel(mode)),
                selected: controller.fit == mode,
                onSelected: (_) => controller.setFit(mode),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: controller.noUpscale,
          onChanged: controller.setNoUpscale,
          contentPadding: EdgeInsets.zero,
          title: const Text('Do not enlarge'),
          subtitle: const Text(
            'Upscaling adds bytes and no detail',
          ),
        ),
      ],
    );
  }

  bool _matchesPreset(int? longEdge) {
    if (longEdge == null) {
      return widget.controller.maxWidth == null &&
          widget.controller.maxHeight == null;
    }
    final w = widget.controller.maxWidth;
    final h = widget.controller.maxHeight;
    return w == longEdge || h == longEdge;
  }

  /// A preset sets the *long* edge and clears the other axis, with `FitMode.width`
  /// left to the user. Setting both axes to the same number with `contain` would
  /// give a square result, which is never what "1080p" means.
  void _applyPreset(int? longEdge) {
    if (longEdge == null) {
      widget.controller
        ..setMaxWidth(null)
        ..setMaxHeight(null);
      _width.clear();
      _height.clear();
      return;
    }
    widget.controller
      ..setMaxWidth(longEdge)
      ..setMaxHeight(null);
    _width.text = longEdge.toString();
    _height.clear();
  }

  String _fitLabel(FitMode mode) => switch (mode) {
    FitMode.contain => 'Fit inside',
    FitMode.cover => 'Fill and crop',
    FitMode.fill => 'Stretch',
    FitMode.width => 'By width',
    FitMode.height => 'By height',
  };
}

class _QualityControls extends StatelessWidget {
  const _QualityControls({required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: controller.quality.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                label: '${controller.quality}',
                onChanged: (value) => controller.setQuality(value.round()),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${controller.quality}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TargetBytesControls extends StatelessWidget {
  const _TargetBytesControls({required this.controller});

  final ResizeController controller;

  static const List<({String label, int bytes})> _presets = [
    (label: 'None', bytes: 0),
    (label: '1 MB', bytes: 1048576),
    (label: '500 KB', bytes: 512000),
    (label: '300 KB', bytes: 307200),
    (label: '100 KB', bytes: 102400),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in _presets)
          ChoiceChip(
            label: Text(preset.label),
            selected: (controller.targetBytes ?? 0) == preset.bytes,
            onSelected: (_) => controller.setTargetBytes(
              preset.bytes == 0 ? null : preset.bytes,
            ),
          ),
      ],
    );
  }
}

class _MetadataControls extends StatelessWidget {
  const _MetadataControls({required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    final sensitive = controller.selectedImages
        .where((i) => i.hasSensitiveTags)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: controller.stripMetadata,
          onChanged: controller.setStripMetadata,
          contentPadding: EdgeInsets.zero,
          title: const Text('Remove metadata'),
          subtitle: const Text(
            'Camera, date and location. Removed by re-encoding, so nothing is '
            'left behind in the file.',
          ),
        ),
        if (sensitive > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$sensitive selected '
                    '${sensitive == 1 ? 'image carries' : 'images carry'} '
                    'location data',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
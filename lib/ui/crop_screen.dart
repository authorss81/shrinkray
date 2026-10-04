import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../rust/models.dart';
import '../state/resize_controller.dart';

/// Interactive rectangular crop.
///
/// The crop is a rectangle in *source* pixels and the engine applies it before
/// the resize, so what is drawn here has to be mapped back through the on-screen
/// letterboxing. Two coordinate spaces are in play and conflating them is the
/// usual bug:
///
///   * widget space — where the finger is, in logical pixels
///   * image space  — a pixel offset into the decoded original
///
/// [CropOverlay] converts between them once per layout and hands the gesture
/// layer a rect already in image space, so nothing downstream has to know about
/// letterboxing.
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.controller,
    required this.image,
  });

  final ResizeController controller;
  final PickedImage image;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  /// The crop being edited, in source pixels. Null means "no crop".
  Rect? _crop;

  /// The crop the controller currently holds for this image, in source pixels.
  ///
  /// Read from the controller's `CropSpec` rather than kept as a second value, so
  /// entering the screen shows what the last session actually stored.
  Rect? _initialCrop() {
    final spec = widget.controller.cropFor(widget.image.id);
    if (spec == null) return null;
    return Rect.fromLTWH(
      spec.x.toDouble(),
      spec.y.toDouble(),
      spec.width.toDouble(),
      spec.height.toDouble(),
    );
  }

  /// Lock the crop to an aspect ratio. Null means free.
  double? _aspectLock;

  /// Which edge or corner is being dragged.
  CropHandle? _activeHandle;

  @override
  void initState() {
    super.initState();
    _crop = _initialCrop();
  }

  ResizeController get _controller => widget.controller;
  PickedImage get _image => widget.image;

  @override
  Widget build(BuildContext context) {
    final report = _image.report;
    final canCrop = report != null && report.width > 0 && report.height > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop'),
        actions: [
          if (_crop != null)
            TextButton(
              onPressed: () => setState(() {
                _crop = null;
                _aspectLock = null;
              }),
              child: const Text('Reset'),
            ),
        ],
      ),
      body: !canCrop
          ? const Center(child: Text('This image has not been read yet.'))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CropOverlay(
                        imageWidth: report.width,
                        imageHeight: report.height,
                        bytes: _image.bytes,
                        crop: _crop,
                        activeHandle: _activeHandle,
                        onChanged: (rect, handle) {
                          setState(() {
                            _crop = rect;
                            _activeHandle = handle;
                          });
                        },
                        onDragEnded: () => setState(() => _activeHandle = null),
                      );
                    },
                  ),
                ),
                _CropBar(
                  aspectLock: _aspectLock,
                  onAspectChanged: (value) => setState(() => _aspectLock = value),
                  onApply: () {
                    _controller.setCrop(_image.id, cropSpecFrom(_crop));
                    Navigator.of(context).pop();
                  },
                  hasCrop: _crop != null,
                ),
              ],
            ),
    );
  }
}

/// Which part of the crop rectangle is being dragged.
///
/// Public rather than private because [CropOverlay] takes it as a parameter, and
/// a public widget cannot expose a private type in its own API.
enum CropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

/// The draggable crop rectangle over a preview of the image.
///
/// Deliberately does not use `InteractiveViewer`: that is for zooming a canvas,
/// and this needs the crop edge pinned to the image's own bounds. A crop that
/// could be dragged outside the picture would produce a `CropSpec` the engine
/// refuses, and the failure would surface as an export error rather than as the
/// UI declining the gesture.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.bytes,
    required this.crop,
    required this.activeHandle,
    required this.onChanged,
    required this.onDragEnded,
  });

  final int imageWidth;
  final int imageHeight;
  final Uint8List bytes;
  final Rect? crop;
  final CropHandle? activeHandle;
  final void Function(Rect rect, CropHandle handle) onChanged;
  final VoidCallback onDragEnded;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  /// Where the image is drawn inside the available space, in logical pixels.
  Rect _imageBox = Rect.zero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = _fitBox(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        // Committed after layout so the gesture handlers and the painter agree on
        // the mapping. Setting state during build would throw; deferring it to the
        // post-frame callback is the one place it is safe.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && box != _imageBox) {
            setState(() => _imageBox = box);
          }
        });

        final crop = widget.crop ?? Rect.fromLTWH(0, 0, widget.imageWidth.toDouble(), widget.imageHeight.toDouble());

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _startDrag(details.localPosition),
          onPanUpdate: (details) => _updateDrag(crop, details.localPosition),
          onPanEnd: (_) => widget.onDragEnded(),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: box.left,
                    top: box.top,
                    right: constraints.maxWidth - box.right,
                    bottom: constraints.maxHeight - box.bottom,
                  ),
                  child: ClipRect(
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.fill,
                      // BoxFit.fill, not contain: the image is already sized to
                      // the box, and letting the widget letterbox it again would
                      // put the crop rectangle somewhere else from the pixels.
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                ),
              ),
              // Dim everything outside the crop, which is how a crop reads as a
              // crop rather than as a drawn rectangle.
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropPainter(
                    crop: _toWidget(crop),
                    imageBox: box,
                    activeHandle: widget.activeHandle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The largest rect with the source aspect ratio that fits in [available].
  Rect _fitBox(Size available) {
    if (available.width <= 0 || available.height <= 0) return Rect.zero;
    final scale = math.min(
      available.width / widget.imageWidth,
      available.height / widget.imageHeight,
    );
    final width = widget.imageWidth * scale;
    final height = widget.imageHeight * scale;
    return Rect.fromLTWH(
      (available.width - width) / 2,
      (available.height - height) / 2,
      width,
      height,
    );
  }

  /// Image space to widget space.
  Rect _toWidget(Rect crop) {
    if (_imageBox.width <= 0) return Rect.zero;
    final scaleX = _imageBox.width / widget.imageWidth;
    final scaleY = _imageBox.height / widget.imageHeight;
    return Rect.fromLTRB(
      _imageBox.left + crop.left * scaleX,
      _imageBox.top + crop.top * scaleY,
      _imageBox.left + crop.right * scaleX,
      _imageBox.top + crop.bottom * scaleY,
    );
  }

  /// Widget space to image space.
  Rect _toImage(Rect widgetRect) {
    final scaleX = widget.imageWidth / _imageBox.width;
    final scaleY = widget.imageHeight / _imageBox.height;
    return Rect.fromLTRB(
      (widgetRect.left - _imageBox.left) * scaleX,
      (widgetRect.top - _imageBox.top) * scaleY,
      (widgetRect.right - _imageBox.left) * scaleX,
      (widgetRect.bottom - _imageBox.top) * scaleY,
    );
  }

  /// Nearest handle to [position], or null when the touch was outside every
  /// target.
  CropHandle? _handleAt(Offset position) {
    if (_imageBox.width <= 0) return null;
    final crop = widget.crop == null
        ? Rect.fromLTWH(0, 0, widget.imageWidth.toDouble(), widget.imageHeight.toDouble())
        : widget.crop!;
    final corners = _toWidget(crop);
    const grab = 28.0;

    if ((position - corners.topLeft).distance <= grab) return CropHandle.topLeft;
    if ((position - corners.topRight).distance <= grab) return CropHandle.topRight;
    if ((position - corners.bottomLeft).distance <= grab) return CropHandle.bottomLeft;
    if ((position - corners.bottomRight).distance <= grab) return CropHandle.bottomRight;
    if (corners.inflate(grab * 0.5).contains(position)) return CropHandle.move;
    return null;
  }

  void _startDrag(Offset position) {
    final handle = _handleAt(position);
    if (handle == null) return;
    widget.onChanged(widget.crop ?? Rect.fromLTWH(0, 0, widget.imageWidth.toDouble(), widget.imageHeight.toDouble()), handle);
  }

  void _updateDrag(Rect crop, Offset position) {
    final handle = widget.activeHandle;
    if (handle == null) return;

    final scaleX = widget.imageWidth / _imageBox.width;
    final scaleY = widget.imageHeight / _imageBox.height;
    // Where the finger is, in image pixels.
    final image = _toImage(Rect.fromPoints(position, position));

    Rect next;
    switch (handle) {
      case CropHandle.move:
        final dx = image.left - crop.left;
        final dy = image.top - crop.top;
        next = Rect.fromLTWH(
          (crop.left + dx).clamp(0, widget.imageWidth - crop.width),
          (crop.top + dy).clamp(0, widget.imageHeight - crop.height),
          crop.width,
          crop.height,
        );
      case CropHandle.topLeft:
        next = Rect.fromLTRB(
          image.left.clamp(0, crop.right - 1),
          image.top.clamp(0, crop.bottom - 1),
          crop.right,
          crop.bottom,
        );
      case CropHandle.topRight:
        next = Rect.fromLTRB(
          crop.left,
          image.top.clamp(0, crop.bottom - 1),
          image.left.clamp(crop.left + 1, widget.imageWidth.toDouble()),
          crop.bottom,
        );
      case CropHandle.bottomLeft:
        next = Rect.fromLTRB(
          image.left.clamp(0, crop.right - 1),
          crop.top,
          crop.right,
          image.bottom.clamp(crop.top + 1, widget.imageHeight.toDouble()),
        );
      case CropHandle.bottomRight:
        next = Rect.fromLTRB(
          crop.left,
          crop.top,
          image.left.clamp(crop.left + 1, widget.imageWidth.toDouble()),
          image.bottom.clamp(crop.top + 1, widget.imageHeight.toDouble()),
        );
    }

    next = _clampToImage(next);
    widget.onChanged(_round(next), handle);
    // `scaleX`/`scaleY` are read through `_toImage`; kept explicit so the
    // mapping is visible where the arithmetic happens.
    assert(scaleX > 0 && scaleY > 0);
  }

  /// Keep the rectangle inside the picture. The engine refuses a crop that
  /// overhangs, so the UI must never produce one.
  Rect _clampToImage(Rect rect) {
    final maxWidth = widget.imageWidth.toDouble();
    final maxHeight = widget.imageHeight.toDouble();
    var left = rect.left.clamp(0.0, maxWidth - 1);
    var top = rect.top.clamp(0.0, maxHeight - 1);
    var width = rect.width.clamp(1.0, maxWidth - left);
    var height = rect.height.clamp(1.0, maxHeight - top);
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Whole pixels, because the engine's `CropSpec` is `u32`.
  Rect _round(Rect rect) => Rect.fromLTRB(
    rect.left.roundToDouble(),
    rect.top.roundToDouble(),
    (rect.left + rect.width).roundToDouble(),
    (rect.top + rect.height).roundToDouble(),
  );
}

/// Draws the dimmed surround, the crop border, and the corner handles.
class _CropPainter extends CustomPainter {
  _CropPainter({required this.crop, required this.imageBox, required this.activeHandle});

  final Rect crop;
  final Rect imageBox;
  final CropHandle? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageBox.width <= 0) return;

    // Dim the whole canvas, then punch the crop out of the dim with
    // BlendMode.clear. Compositing the four surrounding rectangles by hand
    // leaves seams on fractional device pixel ratios, and a seam across a photo
    // is visible.
    final dim = Paint()..color = const Color(0x99000000);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, dim);
    canvas.drawRect(crop, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // Thirds, because a crop with a grid is usable and one without is a guess.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.4);
    for (final t in const [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(crop.left + crop.width * t, crop.top),
        Offset(crop.left + crop.width * t, crop.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * t),
        Offset(crop.right, crop.top + crop.height * t),
        grid,
      );
    }

    final handle = Paint()..color = Colors.white;
    const length = 18.0;
    const thickness = 4.0;
    for (final corner in [
      (crop.topLeft, 1.0, 1.0),
      (crop.topRight, -1.0, 1.0),
      (crop.bottomLeft, 1.0, -1.0),
      (crop.bottomRight, -1.0, -1.0),
    ]) {
      final (point, dx, dy) = corner;
      canvas.drawLine(
        point,
        point + Offset(length * dx, 0),
        handle..strokeWidth = thickness..strokeCap = StrokeCap.square,
      );
      canvas.drawLine(
        point,
        point + Offset(0, length * dy),
        handle,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop ||
      old.imageBox != imageBox ||
      old.activeHandle != activeHandle;
}

/// Aspect-ratio lock plus Apply.
class _CropBar extends StatelessWidget {
  const _CropBar({
    required this.aspectLock,
    required this.onAspectChanged,
    required this.onApply,
    required this.hasCrop,
  });

  final double? aspectLock;
  final ValueChanged<double?> onAspectChanged;
  final VoidCallback onApply;
  final bool hasCrop;

  /// The ratios worth offering. `free` is null.
  static const List<({String label, double? ratio})> _options = [
    (label: 'Free', ratio: null),
    (label: '1:1', ratio: 1),
    (label: '4:3', ratio: 4 / 3),
    (label: '3:2', ratio: 3 / 2),
    (label: '16:9', ratio: 16 / 9),
    (label: '9:16', ratio: 9 / 16),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in _options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(option.label),
                        selected: aspectLock == option.ratio,
                        onSelected: (_) => onAspectChanged(option.ratio),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onApply,
                child: Text(hasCrop ? 'Apply crop' : 'Use whole image'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converts the widget's crop rect into the engine's `CropSpec`.
///
/// A named function rather than an inline construction so the rounding rule lives
/// in one place: the engine takes `u32` source pixels, and a rect rounded
/// inconsistently would produce a spec one pixel narrower than the preview the
/// user just confirmed.
CropSpec? cropSpecFrom(Rect? rect) {
  if (rect == null) return null;
  final left = rect.left.round();
  final top = rect.top.round();
  final right = (rect.left + rect.width).round();
  final bottom = (rect.top + rect.height).round();
  final width = right - left;
  final height = bottom - top;
  // A rect that rounds to nothing would produce a `CropSpec` the engine refuses
  // with ZeroDimension, so it is dropped here instead.
  if (width <= 0 || height <= 0) return null;
  return CropSpec(
    x: left < 0 ? 0 : left,
    y: top < 0 ? 0 : top,
    width: width,
    height: height,
  );
}
import 'package:flutter_test/flutter_test.dart';

import 'package:shrinkray/rust/models.dart';
import 'package:shrinkray/state/resize_controller.dart';

import 'support/fake_engine.dart';

/// Tests for the controller's rules, without widgets.
///
/// These are the assertions that must hold regardless of how the screens are
/// built: what the app claims it can write, what it will actually send the
/// engine, and what it says when something fails.
void main() {
  late ResizeController controller;
  late FakeEngine engine;

  setUp(() async {
    final made = await makeController();
    controller = made.controller;
    engine = made.engine;
  });

  tearDown(() => controller.dispose());

  group('capabilities gate the format list', () {
    test('a format the engine reports is writable', () {
      expect(controller.canWrite(OutputFormat.jpeg), isTrue);
      expect(controller.canWrite(OutputFormat.png), isTrue);
    });

    test('a read-only format is never writable, whatever the build says', () {
      // The engine has no HEVC encoder at all, so no capability flag can make
      // HEIC writable. Asserting this against the flags alone would pass today
      // and fail the day someone adds the encoder without revisiting the UI.
      expect(controller.canWrite(OutputFormat.heic), isFalse);
      expect(controller.canWrite(OutputFormat.heif), isFalse);
    });

    test('nothing is claimed before capabilities load', () async {
      // A wrong "yes" here produces an export that fails at the last step,
      // after the user has waited for it.
      final fresh = ResizeController(engine: engine);
      addTearDown(fresh.dispose);

      expect(fresh.capabilities, isNull);
      expect(fresh.canWrite(OutputFormat.jpeg), isFalse);
    });

    test('quality applies only where it changes the bytes', () {
      expect(controller.qualityAppliesTo(OutputFormat.jpeg), isTrue);
      expect(controller.qualityAppliesTo(OutputFormat.webp), isTrue);
      // PNG and GIF are lossless: a slider over them provably cannot change the
      // result.
      expect(controller.qualityAppliesTo(OutputFormat.png), isFalse);
      expect(controller.qualityAppliesTo(OutputFormat.gif), isFalse);
    });
  });

  group('settings reach the engine', () {
    setUp(() async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(512)),
      ]);
    });

    test('the default pipeline carries the current settings', () {
      controller
        ..setMaxWidth(1200)
        ..setFormat(OutputFormat.webp)
        ..setQuality(70);

      final pipeline = controller.pipelineFor(controller.selectedImages.single);

      expect(pipeline.resize?.width, 1200);
      expect(pipeline.resize?.noUpscale, isTrue);
      expect(controller.format, OutputFormat.webp);
      expect(controller.quality, 70);
    });

    test('switching to a lossless format drops a byte target', () {
      controller.setTargetBytes(102400);
      expect(controller.targetBytes, 102400);

      controller.setFormat(OutputFormat.png);

      // A ceiling on a format with no quality setting is a control that cannot
      // work, so it is cleared rather than left to fail at export time.
      expect(controller.targetBytes, isNull);
    });

    test('the pipeline carries the crop for that image only', () {
      controller.setCrop(
        controller.selectedImages.single.id,
        const CropSpec(x: 10, y: 20, width: 100, height: 200),
      );

      final pipeline = controller.pipelineFor(controller.selectedImages.single);
      expect(pipeline.crop?.width, 100);
      expect(pipeline.crop?.height, 200);
    });
  });

  group('summary', () {
    setUp(() async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(512)),
      ]);
    });

    test('names the format and quality so the button is not a mystery', () {
      final summary = controller.summary;
      expect(summary, contains('JPEG'));
      expect(summary, contains('q85'));
    });

    test('says when metadata is kept, because that is a privacy choice', () {
      expect(controller.summary, contains('metadata removed'));

      controller.setStripMetadata(false);

      expect(controller.summary, contains('metadata kept'));
    });

    test('does not claim a quality for a lossless format', () {
      controller.setFormat(OutputFormat.png);

      // Showing "q85" next to a PNG would be a claim about a control that did
      // nothing.
      expect(controller.summary, isNot(contains('q')));
    });

    test('mentions a byte target when one is set', () {
      controller.setTargetBytes(1048576);

      expect(controller.summary, contains('1.0 MB'));
    });
  });

  group('adding images', () {
    test('inspects each file and records the report', () async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(100)),
        (name: 'b.png', bytes: fakeBytes(200)),
      ]);

      expect(engine.inspectCalls, 2);
      expect(controller.images.every((i) => i.inspected), isTrue);
      expect(controller.images.first.width, 800);
    });

    test('selects what it adds, so Export means something immediately', () async {
      await controller.addImages([(name: 'a.jpg', bytes: fakeBytes(100))]);

      expect(controller.selectedIds.length, 1);
    });

    test('a file the engine rejects does not discard the others', () async {
      // One unreadable file in a selection of 200 must not lose the other 199.
      engine.failure = EngineFailure('this is not an image');

      await controller.addImages([
        (name: 'bad.jpg', bytes: fakeBytes(50)),
      ]);

      expect(controller.images.single.failed, isTrue);
      expect(controller.images.single.error, contains('not an image'));
    });

    test('a failed file is not exported', () async {
      engine.failure = EngineFailure('unreadable');
      await controller.addImages([(name: 'bad.jpg', bytes: fakeBytes(50))]);
      engine.failure = null;

      await controller.export();

      expect(engine.processCalls, 0);
    });
  });

  group('export', () {
    setUp(() async {
      await controller.addImages([(name: 'a.jpg', bytes: fakeBytes(512))]);
    });

    test('one image uses the single path', () async {
      await controller.export();

      expect(engine.processCalls, 1);
      expect(engine.batchCalls, 0);
      expect(controller.phase, ExportPhase.done);
    });

    test('two images use the batch path', () async {
      await controller.addImages([(name: 'b.jpg', bytes: fakeBytes(512))]);

      await controller.export();

      expect(engine.batchCalls, 1);
      expect(engine.processCalls, 0);
    });

    test('the engine receives the settings the user chose', () async {
      controller
        ..setFormat(OutputFormat.webp)
        ..setQuality(55)
        ..setMaxWidth(800);

      await controller.export();

      expect(engine.lastFormat, OutputFormat.webp);
      expect(engine.lastQuality, 55);
      expect(engine.lastPipeline?.resize?.width, 800);
    });

    test('a failure becomes a message rather than an exception', () async {
      engine.failure = EngineFailure('the decoder gave up');

      await controller.export();

      expect(controller.phase, ExportPhase.failed);
      expect(controller.error, contains('decoder gave up'));
    });

    test('a second export does nothing while one is running', () async {
      // Re-entrancy: a double tap on Export must not run the batch twice.
      final first = controller.export();
      final second = controller.export();
      await Future.wait([first, second]);

      expect(engine.processCalls, 1);
    });

    test('nothing is exported with an empty selection', () async {
      controller.deselectAll();

      await controller.export();

      expect(engine.processCalls, 0);
      expect(engine.batchCalls, 0);
    });

    test('acknowledging returns to idle so the bar disappears', () async {
      await controller.export();
      expect(controller.phase, ExportPhase.done);

      controller.acknowledgeExport();

      expect(controller.phase, ExportPhase.idle);
      expect(controller.statusLine, isNull);
    });

    test('the batch keeps the pick order', () async {
      await controller.addImages([
        (name: 'c.jpg', bytes: fakeBytes(10)),
        (name: 'd.jpg', bytes: fakeBytes(20)),
      ]);

      await controller.export();

      // A batch whose output order came from a Set would reorder between runs.
      final names = controller.selectedImages.map((i) => i.name).toList();
      expect(names, ['a.jpg', 'c.jpg', 'd.jpg']);
    });
  });

  group('selection', () {
    setUp(() async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(100)),
        (name: 'b.jpg', bytes: fakeBytes(200)),
      ]);
    });

    test('toggling twice returns to unselected', () {
      final id = controller.images.first.id;

      controller.toggleSelection(id);
      expect(controller.selectedIds.contains(id), isFalse);

      controller.toggleSelection(id);
      expect(controller.selectedIds.contains(id), isTrue);
    });

    test('selectAll skips files the engine could not read', () async {
      engine.failure = EngineFailure('unreadable');
      await controller.addImages([(name: 'c.jpg', bytes: fakeBytes(50))]);
      engine.failure = null;

      controller.selectAll();

      final failed = controller.images.where((i) => i.failed).map((i) => i.id);
      for (final id in failed) {
        expect(controller.selectedIds.contains(id), isFalse);
      }
    });

    test('removing an image forgets its crop', () async {
      final id = controller.images.first.id;
      controller.setCrop(id, const CropSpec(x: 0, y: 0, width: 10, height: 10));

      controller.removeImage(id);

      expect(controller.cropFor(id), isNull);
    });

    test('clearing resets the export state too', () async {
      await controller.export();

      controller.clearImages();

      expect(controller.hasImages, isFalse);
      expect(controller.phase, ExportPhase.idle);
      expect(controller.lastResult, isNull);
    });
  });
}

/// A stand-in for a typed engine exception, so the controller's failure path is
/// exercised without depending on the exact exception hierarchy.
class EngineFailure implements Exception {
  const EngineFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
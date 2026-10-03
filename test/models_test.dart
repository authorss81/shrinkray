import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkray/rust/models.dart';

void main() {
  group('OutputFormat', () {
    test('serialises lowercase, matching the Rust serde convention', () {
      expect(OutputFormat.jpeg.toJson(), 'jpeg');
      expect(OutputFormat.png.toJson(), 'png');
      expect(OutputFormat.webp.toJson(), 'webp');
      expect(OutputFormat.gif.toJson(), 'gif');
      expect(OutputFormat.tiff.toJson(), 'tiff');
      expect(OutputFormat.bmp.toJson(), 'bmp');
      expect(OutputFormat.ico.toJson(), 'ico');
      expect(OutputFormat.avif.toJson(), 'avif');
    });

    test('round-trips every value', () {
      for (final format in OutputFormat.values) {
        expect(OutputFormat.fromJson(format.toJson()), format);
      }
    });
  });

  group('FitMode', () {
    test('serialises snake_case, matching the Rust serde convention', () {
      expect(FitMode.contain.toJson(), 'contain');
      expect(FitMode.cover.toJson(), 'cover');
      expect(FitMode.fill.toJson(), 'fill');
      expect(FitMode.width.toJson(), 'width');
      expect(FitMode.height.toJson(), 'height');
    });
  });

  group('ResampleFilter', () {
    test('catmullRom serialises with an underscore, not camelCase', () {
      // The Rust side is `#[serde(rename_all = "snake_case")]`, so
      // `CatmullRom` becomes `catmull_rom`. Sending `catmullRom` would be a
      // silent "bad request" from the engine.
      expect(ResampleFilter.catmullRom.toJson(), 'catmull_rom');
      expect(ResampleFilter.lanczos3.toJson(), 'lanczos3');
    });

    test('rejects an unknown filter rather than guessing', () {
      expect(() => ResampleFilter.fromJson('bicubic'), throwsArgumentError);
    });
  });

  group('Pipeline', () {
    test('serialises with the exact keys the engine expects', () {
      const pipeline = Pipeline(
        resize: ResizeSpec(width: 1920, fit: FitMode.width),
      );
      final json = pipeline.toJson();
      expect(json['crop'], isNull);
      expect(json['orientation'], isNull);
      expect(json['strip_metadata'], isTrue);
      final resize = json['resize'] as Map<String, Object?>;
      expect(resize['width'], 1920);
      expect(resize['height'], isNull);
      expect(resize['fit'], 'width');
      expect(resize['filter'], 'lanczos3');
      expect(resize['no_upscale'], isTrue);
    });

    test('stripMetadata defaults to true', () {
      // Phone photos carry GPS. The default must be to strip, not to keep.
      const pipeline = Pipeline();
      expect(pipeline.stripMetadata, isTrue);
      expect((pipeline.toJson())['strip_metadata'], isTrue);
    });

    test('noUpscale defaults to true', () {
      // Upscaling past native resolution adds bytes and zero detail.
      const spec = ResizeSpec(width: 8000);
      expect(spec.noUpscale, isTrue);
    });
  });

  group('Requests.process', () {
    test('builds the envelope the engine parses', () {
      const pipeline = Pipeline(
        resize: ResizeSpec(width: 400, fit: FitMode.width),
      );
      final body = Requests.process(
        pipeline: pipeline,
        format: OutputFormat.jpeg,
        imageBytes: [1, 2, 3],
        name: 'photo.jpg',
      );
      expect(body, contains('"format":"jpeg"'));
      expect(body, contains('"name":"photo.jpg"'));
      expect(body, contains('"quality":85'));
      // [1, 2, 3] as base64.
      expect(body, contains('"data_base64":"AQID"'));
    });
  });

  group('ProcessResult', () {
    test('savedPercent is honest at the boundaries', () {
      ProcessResult base({required int input, required int output}) =>
          ProcessResult(
            outputName: 'a.jpg',
            bytes: const [],
            inputBytes: input,
            outputBytes: output,
            width: 10,
            height: 10,
            qualityUsed: 80,
            targetMet: true,
            detectedFormat: OutputFormat.jpeg,
          );
      expect(base(input: 100, output: 25).savedPercent, 75.0);
      expect(base(input: 0, output: 0).savedPercent, 0.0);
      expect(base(input: 100, output: 100).savedPercent, 0.0);
    });
  });

  group('BatchReport', () {
    test('counts successes and failures', () {
      BatchOutcome outcome({required String? error}) => BatchOutcome(
        id: '1',
        name: 'a.jpg',
        outputName: 'a.jpg',
        inputBytes: 10,
        outputBytes: 5,
        width: 10,
        height: 10,
        qualityUsed: 80,
        targetMet: true,
        error: error,
      );
      final report = BatchReport(
        outcomes: [outcome(error: null), outcome(error: 'broken')],
        cancelled: false,
      );
      expect(report.succeeded, 1);
      expect(report.failed, 1);
      expect(report.outcomes.first.ok, isTrue);
      expect(report.outcomes.last.ok, isFalse);
    });
  });
}

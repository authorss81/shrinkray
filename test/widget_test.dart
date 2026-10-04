import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shrinkray/state/resize_controller.dart';
import 'package:shrinkray/ui/home_screen.dart';
import 'package:shrinkray/ui/settings_sheet.dart';

import 'support/fake_engine.dart';

void main() {
  late ResizeController controller;

  setUp(() async {
    final made = await makeController();
    controller = made.controller;
  });

  tearDown(() => controller.dispose());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(controller: controller)),
    );
    await tester.pump();
  }

  group('empty state', () {
    testWidgets('offers a way to pick images', (tester) async {
      await pumpHome(tester);

      expect(find.text('No images yet'), findsOneWidget);
      expect(find.text('Choose images'), findsOneWidget);
    });

    testWidgets('says photos stay on the device', (tester) async {
      // The privacy claim is the reason to use this app over a web uploader, so
      // it belongs on the first screen rather than in a settings page.
      await pumpHome(tester);

      expect(find.textContaining('stay on this device'), findsOneWidget);
    });

    testWidgets('has no export button with nothing selected', (tester) async {
      await pumpHome(tester);

      // An export button that cannot do anything is a dead control.
      expect(find.text('Export'), findsNothing);
    });
  });

  group('with images', () {
    setUp(() async {
      await controller.addImages([
        (name: 'holiday.jpg', bytes: fakeBytes(2048)),
      ]);
    });

    testWidgets('shows the file name and its dimensions', (tester) async {
      await pumpHome(tester);

      expect(find.text('holiday.jpg'), findsOneWidget);
      // The fake reports 800x600. If the UI showed a file manager's idea of the
      // size instead, this would differ.
      expect(find.text('800x600'), findsOneWidget);
    });

    testWidgets('reveals the export controls once something is picked', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('summarises what the export will do', (tester) async {
      await pumpHome(tester);

      // The defaults must be visible before the user commits, so "Resize" is
      // never a button whose meaning is hidden.
      expect(find.textContaining('JPEG'), findsOneWidget);
      expect(find.textContaining('q85'), findsOneWidget);
    });

    testWidgets('settings sheet opens and reflects the current format', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsSheet), findsOneWidget);
      expect(find.text('Output format'), findsOneWidget);
    });

    testWidgets('changing quality changes the summary', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();

      // Drive the controller directly rather than hunting for a slider pixel:
      // the assertion is about the summary following the setting, not about
      // where the slider is.
      controller.setQuality(40);
      await tester.pumpAndSettle();

      expect(find.textContaining('q40'), findsOneWidget);
    });
  });

  group('multiple images', () {
    testWidgets('counts the selection on the action bar', (tester) async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(100)),
        (name: 'b.jpg', bytes: fakeBytes(200)),
      ]);
      await pumpHome(tester);

      expect(find.text('Resize 2'), findsOneWidget);
    });

    testWidgets('deselecting drops the count', (tester) async {
      await controller.addImages([
        (name: 'a.jpg', bytes: fakeBytes(100)),
        (name: 'b.jpg', bytes: fakeBytes(200)),
      ]);
      await pumpHome(tester);

      controller.deselectAll();
      await tester.pump();

      expect(find.text('Resize 2'), findsNothing);
      expect(find.text('Resize'), findsOneWidget);
    });
  });
}

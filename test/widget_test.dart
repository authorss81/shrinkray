import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shrinkray/main.dart';

void main() {
  testWidgets('placeholder shell renders the app title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ShrinkRayApp());

    expect(find.text('ShrinkRay'), findsWidgets);
    // The engine is not built in a unit-test environment, so the probe page
    // must show its loading state rather than crashing.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

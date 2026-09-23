import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';

void main() {
  testWidgets('the Linux scanner offers Restart camera before any picture', (
    tester,
  ) async {
    // The scanner is platform specific; this covers the Linux one.
    if (!Platform.isLinux) return;
    await tester.pumpWidget(const InventorinatorApp());
    await tester.ensureVisible(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();

    // With no camera, or one that has not sent a picture yet, the preview area
    // offers a way to retry without closing the scanner.
    final retry = find.byKey(const Key('restart-linux-camera-retry'));
    expect(retry, findsOneWidget);
    expect(find.text('Restart camera'), findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(retry).onPressed,
      isNotNull,
      reason: 'the button is usable',
    );

    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/renderer_preference.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('renderer'));
  tearDown(() => directory.deleteSync(recursive: true));

  File preferenceFile() => File('${directory.path}/renderer');

  test('the launcher file holds only an explicit choice', () async {
    expect(await loadRendererChoice(directory), RendererChoice.platformDefault);

    await saveRendererChoice(directory, RendererChoice.impeller);
    expect(preferenceFile().readAsStringSync(), 'impeller');
    expect(await loadRendererChoice(directory), RendererChoice.impeller);

    await saveRendererChoice(directory, RendererChoice.skia);
    expect(await loadRendererChoice(directory), RendererChoice.skia);

    // Default removes the file so the launcher uses the platform default.
    await saveRendererChoice(directory, RendererChoice.platformDefault);
    expect(preferenceFile().existsSync(), isFalse);
  });

  test('Linux defaults to Skia', () {
    expect(
      platformDefaultRenderer,
      Platform.isLinux ? RendererChoice.skia : RendererChoice.impeller,
    );
  });

  testWidgets('Personalization saves the renderer for the next launch', (
    tester,
  ) async {
    await tester.runAsync(
      () => saveRendererChoice(directory, RendererChoice.impeller),
    );
    Future<void> settleFileIo() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RendererPreferenceTile(directory: directory)),
        ),
      ),
    );
    await settleFileIo();
    await tester.pump();
    expect(find.text('Impeller'), findsOneWidget);
    expect(find.text('Graphics engine used to draw the app.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('renderer-preference-dropdown')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Skia').last);
      // The dropdown reports the choice once its menu route has closed.
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(preferenceFile().readAsStringSync(), 'skia');
    expect(
      find.text('Restart Inventorinator to switch renderers.'),
      findsOneWidget,
    );
  });
}

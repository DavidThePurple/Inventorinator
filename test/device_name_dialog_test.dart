import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/device_name_dialog.dart';

void main() {
  testWidgets('saving a focused device name closes cleanly', (tester) async {
    String? savedName;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                savedName = await showDeviceNameDialog(
                  context,
                  initialName: 'Android device',
                );
              },
              child: const Text('Rename'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-name')),
      'Workshop phone',
    );
    await tester.tap(find.byKey(const Key('save-device-name')));
    await tester.pumpAndSettle();

    expect(savedName, 'Workshop phone');
    expect(tester.takeException(), isNull);
  });
}

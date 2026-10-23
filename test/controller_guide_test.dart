import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';

void main() {
  testWidgets('a controller button opens the controller guide', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryHome(
          persistedState: encodeWorkshopState(
            inventory: [
              InventoryItem(
                id: 'CONTROLLER-ITEM',
                name: 'Controller test item',
                type: InventoryType.other,
                compatibility: const [],
                added: DateTime(2026),
                cost: 0,
                quantity: 1,
                color: Colors.grey,
              ),
            ],
            vendors: const [],
            brands: const [],
            products: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('controller-guide-dialog')), findsOneWidget);
    expect(find.text('Right stick click'), findsOneWidget);
  });
}

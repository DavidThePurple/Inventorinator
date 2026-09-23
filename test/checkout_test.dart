import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/workshop_delta.dart';

CheckoutRecord _checkout({
  double quantity = 4,
  double returned = 0,
  DateTime? due,
  String id = 'CO-1',
}) => CheckoutRecord(
  id: id,
  itemId: 'INV-SPOOL',
  itemName: 'PLA spool',
  quantity: quantity,
  borrower: 'Sam',
  checkedOutAt: DateTime.utc(2026, 9, 20),
  expectedReturnAt: due,
  returnedQuantity: returned,
);

InventoryItem _item({double quantity = 10}) => InventoryItem(
  id: 'INV-SPOOL',
  name: 'PLA spool',
  type: InventoryType.other,
  compatibility: const [],
  added: DateTime(2026, 1),
  cost: 0,
  color: Colors.grey,
  quantity: quantity,
);

String _state({
  List<CheckoutRecord> checkouts = const [],
  double quantity = 10,
}) => encodeWorkshopState(
  inventory: [_item(quantity: quantity)],
  vendors: const [],
  brands: const [],
  products: const [],
  checkouts: checkouts,
);

void main() {
  group('CheckoutRecord', () {
    test('what is out is the quantity minus what came back', () {
      expect(_checkout().outstanding, 4);
      expect(_checkout(returned: 1.5).outstanding, 2.5);
      expect(_checkout(returned: 4).isReturned, isTrue);
      expect(_checkout(returned: 4).outstanding, 0);
    });

    test('partial returns add up and never exceed what is out', () {
      final when = DateTime.utc(2026, 9, 21);
      final first = _checkout().returned(1, when);
      final second = first.returned(2, when);
      final over = second.returned(99, when);

      expect(first.outstanding, 3);
      expect(second.outstanding, 1);
      expect(over.returnedQuantity, 4);
      expect(over.isReturned, isTrue);
      expect(over.lastReturnedAt, when);
    });

    test('is overdue only while stock is out past its return date', () {
      final due = DateTime.utc(2026, 9, 22);
      final now = DateTime.utc(2026, 9, 23);

      expect(_checkout(due: due).isOverdue(now), isTrue);
      expect(_checkout(due: due).isOverdue(DateTime.utc(2026, 9, 21)), isFalse);
      expect(_checkout(due: due, returned: 4).isOverdue(now), isFalse);
      expect(_checkout().isOverdue(now), isFalse, reason: 'no return date');
    });

    test('survives saving and loading', () {
      final saved = decodeWorkshopState(
        _state(
          checkouts: [_checkout(due: DateTime.utc(2026, 9, 25), returned: 1)],
        ),
      )!;

      final loaded = saved.checkouts.single;
      expect(loaded.borrower, 'Sam');
      expect(loaded.quantity, 4);
      expect(loaded.returnedQuantity, 1);
      expect(loaded.expectedReturnAt, DateTime.utc(2026, 9, 25));
      expect(loaded.kind, CheckoutBorrowerKind.person);
    });
  });

  group('sync gating', () {
    late Directory directory;
    late LocalDatabase database;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('inventorinator-co-');
      database = await LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      );
    });

    tearDown(() async {
      database.close();
      await directory.delete(recursive: true);
    });

    Future<void> queueCheckoutAndItem() async {
      await database.queueWorkshopChanges([
        const WorkshopEntityChange(
          entityType: 'checkouts',
          entityId: 'CO-1',
          fields: {'borrower': 'Sam', 'quantity': 4},
        ),
        const WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'INV-SPOOL',
          fields: {'name': 'PLA spool'},
        ),
      ]);
    }

    test(
      'checkouts stay on this device until the workspace shares them',
      () async {
        await queueCheckoutAndItem();

        expect(database.checkoutSyncEnabled, isFalse);
        expect(
          database.loadPendingWorkshopChanges().map((c) => c.change.entityType),
          ['inventory'],
          reason: 'only non-checkout changes upload while sharing is off',
        );

        database.setCheckoutSyncEnabled(true);
        expect(
          database.loadPendingWorkshopChanges().map((c) => c.change.entityType),
          containsAll(['inventory', 'checkouts']),
          reason: 'the waiting checkouts go up once sharing is turned on',
        );
      },
    );

    test('the setting is remembered across restarts', () async {
      database.setCheckoutSyncEnabled(true);
      database.close();

      database = await LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      );
      expect(database.checkoutSyncEnabled, isTrue);
    });
  });

  group('in the app', () {
    Future<void> pumpHome(WidgetTester tester, String state) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: InventoryHome(persistedState: state)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an item can be checked out, partly returned, and returned', (
      tester,
    ) async {
      await pumpHome(tester, _state());
      await tester.tap(find.byKey(const Key('inventory-card-INV-SPOOL')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('item-checkouts')));
      expect(
        tester.widget<Text>(find.byKey(const Key('checkout-summary'))).data,
        '10 total · 0 out · 10 available',
      );

      await tester.tap(find.byKey(const Key('check-out-item')));
      await tester.pumpAndSettle();
      // Needs someone to give it to, and no more than is available.
      await tester.tap(find.byKey(const Key('checkout-confirm')));
      await tester.pump();
      expect(find.text('Enter a person or project.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('checkout-borrower')), 'Sam');
      await tester.enterText(find.byKey(const Key('checkout-quantity')), '11');
      await tester.tap(find.byKey(const Key('checkout-confirm')));
      await tester.pump();
      expect(find.text('Only 10 is available.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('checkout-quantity')), '4');
      await tester.tap(find.byKey(const Key('checkout-confirm')));
      await tester.pumpAndSettle();

      // The total owned did not change; only what is out and what is left.
      expect(
        tester.widget<Text>(find.byKey(const Key('checkout-summary'))).data,
        '10 total · 4 out · 6 available',
      );
      expect(find.textContaining('Sam · 4'), findsOneWidget);

      await tester.tap(find.textContaining('Return').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('return-quantity')), '1');
      await tester.tap(find.byKey(const Key('return-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('checkout-summary'))).data,
        '10 total · 3 out · 7 available',
      );
      expect(find.textContaining('Sam · 3 of 4'), findsOneWidget);

      await tester.tap(find.textContaining('Return').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('return-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('checkout-summary'))).data,
        '10 total · 0 out · 10 available',
      );
    });

    testWidgets('an overdue checkout raises an alert', (tester) async {
      await pumpHome(
        tester,
        _state(
          checkouts: [
            _checkout(
              due: DateTime.now().toUtc().subtract(const Duration(days: 2)),
            ),
          ],
        ),
      );

      final badge = tester.widget<Badge>(
        find.descendant(
          of: find.byKey(const Key('moisture-alerts')),
          matching: find.byType(Badge),
        ),
      );
      expect(badge.isLabelVisible, isTrue);
      tester
          .widget<OutlinedButton>(find.byKey(const Key('moisture-alerts')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('OVERDUE RETURNS'), findsOneWidget);
      expect(find.textContaining('Sam has 4'), findsOneWidget);
    });

    testWidgets('Stockroom lists who has what', (tester) async {
      await pumpHome(tester, _state(checkouts: [_checkout()]));
      await tester.tap(find.byKey(const Key('open-stockroom')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checked out'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkout-group-sam')), findsOneWidget);
      expect(find.textContaining('PLA spool · 4'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';

MachineRecord _machine({
  String? timerLabel,
  DateTime? started,
  Duration? span,
}) {
  const base = MachineRecord(
    id: 'MCH-DRYER',
    name: 'Filament dryer',
    model: '',
    address: '',
    typeId: 'TYPE-DRYER',
  );
  return started == null
      ? base
      : base.withTimer(
          label: timerLabel ?? '',
          startedAt: started,
          duration: span ?? const Duration(hours: 1),
        );
}

String _state(List<MachineRecord> machines) => encodeWorkshopState(
  inventory: const [],
  vendors: const [],
  brands: const [],
  products: const [],
  machineTypes: const [MachineTypeRecord(id: 'TYPE-DRYER', name: 'Dryer')],
  machines: machines,
);

void main() {
  group('MachineRecord timer', () {
    test('has no timer by default', () {
      final machine = _machine();

      expect(machine.hasTimer, isFalse);
      expect(machine.timerFinished(DateTime.now()), isFalse);
      expect(machine.timerRemaining(DateTime.now()), Duration.zero);
    });

    test('counts down and finishes from the clock alone', () {
      final start = DateTime.utc(2026, 9, 23, 12);
      final machine = _machine(started: start, span: const Duration(hours: 2));

      expect(
        machine.timerRemaining(start.add(const Duration(minutes: 30))),
        const Duration(hours: 1, minutes: 30),
      );
      expect(
        machine.timerFinished(start.add(const Duration(hours: 1, minutes: 59))),
        isFalse,
      );
      expect(
        machine.timerFinished(start.add(const Duration(hours: 2))),
        isTrue,
      );
      expect(
        machine.timerRemaining(start.add(const Duration(hours: 5))),
        Duration.zero,
      );
      expect(machine.timerEndsAt, start.add(const Duration(hours: 2)));
    });

    test('clearing the timer leaves the rest of the machine alone', () {
      final machine = _machine(
        timerLabel: 'PETG',
        started: DateTime.utc(2026, 9, 23),
      ).withoutTimer();

      expect(machine.hasTimer, isFalse);
      expect(machine.timerLabel, '');
      expect(machine.name, 'Filament dryer');
      expect(machine.typeId, 'TYPE-DRYER');
    });

    test('survives saving and loading, and old records load without one', () {
      final start = DateTime.utc(2026, 9, 23, 12, 30);
      final saved = decodeWorkshopState(
        _state([
          _machine(
            timerLabel: 'PETG drying',
            started: start,
            span: const Duration(minutes: 90),
          ),
        ]),
      )!;

      final loaded = saved.machines.single;
      expect(loaded.timerLabel, 'PETG drying');
      expect(loaded.timerStartedAt, start);
      expect(loaded.timerDuration, const Duration(minutes: 90));

      final idle = decodeWorkshopState(_state([_machine()]))!.machines.single;
      expect(idle.hasTimer, isFalse);
    });
  });

  group('machine timer in the app', () {
    Future<void> pumpHome(
      WidgetTester tester,
      List<MachineRecord> machines,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: InventoryHome(persistedState: _state(machines))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a finished timer raises an alert that opens the machine', (
      tester,
    ) async {
      await pumpHome(tester, [
        _machine(
          timerLabel: 'PETG drying',
          started: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        ),
      ]);

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
      expect(find.text('TIMERS'), findsOneWidget);
      expect(find.text('PETG drying finished'), findsOneWidget);

      await tester.tap(find.byKey(const Key('machine-timer-alert-MCH-DRYER')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('machine-details-MCH-DRYER')),
        findsOneWidget,
      );
      expect(find.text('Finished'), findsOneWidget);

      await tester.tap(find.byKey(const Key('machine-timer-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('machine-timer-start')), findsOneWidget);
    });

    testWidgets('a timer can be started from the machine details', (
      tester,
    ) async {
      await pumpHome(tester, [_machine()]);
      // Machines list beside inventory in the everything view.
      await tester.tap(find.byKey(const Key('catalog-record-MCH-DRYER')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('machine-timer-panel')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('machine-timer-start')))
            .onPressed,
        isNull,
        reason: 'a duration is needed first',
      );
      await tester.enterText(
        find.byKey(const Key('machine-timer-label')),
        'Benchy',
      );
      await tester.tap(find.byKey(const Key('machine-timer-preset-120')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('machine-timer-start')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('machine-timer-status')), findsOneWidget);
      expect(find.text('Benchy'), findsOneWidget);
      expect(find.byKey(const Key('machine-timer-clear')), findsOneWidget);
      expect(find.text('Stop timer'), findsOneWidget);

      await tester.tap(find.byKey(const Key('machine-timer-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('machine-timer-start')), findsOneWidget);
    });
  });
}

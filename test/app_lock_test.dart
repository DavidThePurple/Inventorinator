import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/app_lock.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';

/// Few PBKDF2 rounds keep the tests fast; each stored hash records its count.
AppLockController _controller(
  LocalDatabase database, {
  DateTime Function()? clock,
}) => AppLockController(database, iterations: 10, clock: clock);

void main() {
  late Directory directory;
  late LocalDatabase database;
  late DateTime now;
  final controllers = <AppLockController>[];

  AppLockController make() {
    final controller = _controller(database, clock: () => now);
    controllers.add(controller);
    return controller;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventorinator-lock-');
    database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    now = DateTime.utc(2026, 9, 23, 12);
  });

  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    database.close();
    await directory.delete(recursive: true);
  });

  group('controller', () {
    test('is off by default: no PIN, never locked', () {
      final lock = make();

      expect(lock.hasPin, isFalse);
      expect(lock.locked, isFalse);
      lock.lock();
      expect(lock.locked, isFalse);
    });

    test('setting a PIN returns a key, and the app asks again next launch', () {
      final lock = make();

      final key = lock.setPin('4821');

      expect(key, matches(RegExp(r'^([0-9A-Z]{4}-){4}[0-9A-Z]{4}$')));
      expect(lock.hasPin, isTrue);
      expect(lock.locked, isFalse, reason: 'setting a PIN does not lock');
      lock.lock();
      expect(lock.locked, isTrue);
      expect(lock.unlock('0000'), AppLockResult.wrong);
      expect(lock.locked, isTrue);
      expect(lock.unlock('4821'), AppLockResult.success);
      expect(lock.locked, isFalse);

      final restarted = make();
      expect(restarted.locked, isTrue);
      expect(restarted.unlock('4821'), AppLockResult.success);
    });

    test('rejects PINs that are not 4 to 12 digits', () {
      final lock = make();

      expect(lock.setPin('123'), isNull);
      expect(lock.setPin('1234567890123'), isNull);
      expect(lock.setPin('12ab'), isNull);
      expect(lock.hasPin, isFalse);
    });

    test('stores only salted hashes of the PIN and key', () {
      final lock = make();
      final key = lock.setPin('4821')!;

      final stored = [
        for (final name in [
          'app_lock_pin_hash',
          'app_lock_pin_salt',
          'app_lock_key_hash',
          'app_lock_key_salt',
        ])
          database.loadStringPreference(name, fallback: ''),
      ];
      expect(stored.every((value) => value.isNotEmpty), isTrue);
      for (final value in stored) {
        expect(value.contains('4821'), isFalse);
        expect(value.contains(key.replaceAll('-', '')), isFalse);
      }
    });

    test(
      'five wrong PINs lock out attempts, and the wait survives restart',
      () {
        final lock = make();
        lock.setPin('4821');
        lock.lock();

        for (var i = 0; i < 5; i++) {
          expect(lock.unlock('0000'), AppLockResult.wrong);
        }
        expect(lock.lockoutRemaining, const Duration(seconds: 30));
        // Even the right PIN is refused while locked out.
        expect(lock.unlock('4821'), AppLockResult.lockedOut);

        final restarted = make();
        expect(restarted.unlock('4821'), AppLockResult.lockedOut);

        now = now.add(const Duration(seconds: 31));
        expect(restarted.unlock('4821'), AppLockResult.success);
        expect(restarted.lockoutRemaining, Duration.zero);
      },
    );

    test('the wait doubles with each further miss', () {
      final lock = make();
      lock.setPin('4821');
      lock.lock();
      for (var i = 0; i < 5; i++) {
        lock.unlock('0000');
      }
      now = now.add(const Duration(seconds: 31));

      lock.unlock('0000');

      expect(lock.lockoutRemaining, const Duration(seconds: 60));
    });

    test('changing and removing the PIN both require the current PIN', () {
      final lock = make();
      lock.setPin('4821');

      expect(lock.changePin('9999', '1357'), AppLockResult.wrong);
      expect(lock.changePin('4821', '1357'), AppLockResult.success);
      lock.lock();
      expect(lock.unlock('4821'), AppLockResult.wrong);
      expect(lock.unlock('1357'), AppLockResult.success);

      expect(lock.removePin('0000'), AppLockResult.wrong);
      expect(lock.hasPin, isTrue);
      expect(lock.removePin('1357'), AppLockResult.success);
      expect(lock.hasPin, isFalse);
      expect(make().locked, isFalse);
    });

    test(
      'idle timeout locks after the chosen time, and activity resets it',
      () {
        final lock = make();
        lock.setPin('4821');
        lock.setTimeoutMinutes(5);

        now = now.add(const Duration(minutes: 4));
        lock.recordActivity();
        now = now.add(const Duration(minutes: 4));
        lock.checkIdle();
        expect(lock.locked, isFalse);

        now = now.add(const Duration(minutes: 2));
        lock.checkIdle();
        expect(lock.locked, isTrue);
        expect(make().timeoutMinutes, 5);
      },
    );

    test('never locks on idle when the timeout is off', () {
      final lock = make();
      lock.setPin('4821');

      now = now.add(const Duration(days: 2));
      lock.checkIdle();

      expect(lock.locked, isFalse);
    });

    test(
      'the unlock key works typed loosely and only against its own PIN set',
      () {
        final lock = make();
        final key = lock.setPin('4821')!;

        expect(lock.checkUnlockKey('wrong-key'), AppLockResult.wrong);
        expect(
          lock.checkUnlockKey(key.toLowerCase().replaceAll('-', ' ')),
          AppLockResult.success,
        );
      },
    );

    test('forgot-PIN: the key sets a new PIN, issues a new key, and stays locked until saved', () {
      final lock = make();
      final oldKey = lock.setPin('4821')!;
      lock.lock();

      final outcome = lock.resetWithUnlockKey(oldKey, newPin: '2468');

      expect(outcome.result, AppLockResult.success);
      expect(outcome.newKey, isNotNull);
      expect(outcome.newKey, isNot(oldKey));
      expect(
        lock.locked,
        isTrue,
        reason: 'stays locked until the key is saved',
      );
      expect(lock.checkUnlockKey(oldKey), AppLockResult.wrong);
      lock.finishReset();
      expect(lock.locked, isFalse);
      lock.lock();
      expect(lock.unlock('4821'), AppLockResult.wrong);
      expect(lock.unlock('2468'), AppLockResult.success);
      expect(lock.checkUnlockKey(outcome.newKey!), AppLockResult.success);
    });

    test('forgot-PIN: the key can turn the lock off', () {
      final lock = make();
      final key = lock.setPin('4821')!;
      lock.lock();

      final outcome = lock.resetWithUnlockKey(key);

      expect(outcome.result, AppLockResult.success);
      expect(lock.hasPin, isFalse);
      expect(lock.locked, isFalse);
      expect(make().locked, isFalse);
    });

    test('a wrong key never unlocks and counts toward the lockout', () {
      final lock = make();
      lock.setPin('4821');
      lock.lock();

      for (var i = 0; i < 5; i++) {
        expect(
          lock.resetWithUnlockKey('AAAA-AAAA-AAAA-AAAA-AAAA').result,
          AppLockResult.wrong,
        );
      }

      expect(lock.locked, isTrue);
      expect(lock.lockoutRemaining, greaterThan(Duration.zero));
    });

    test('a new key needs the PIN and retires the old key', () {
      final lock = make();
      final oldKey = lock.setPin('4821')!;

      expect(lock.regenerateUnlockKey('0000').key, isNull);
      final fresh = lock.regenerateUnlockKey('4821').key!;

      expect(fresh, isNot(oldKey));
      expect(lock.checkUnlockKey(oldKey), AppLockResult.wrong);
      expect(lock.checkUnlockKey(fresh), AppLockResult.success);
    });
  });

  group('lock screen', () {
    Future<AppLockController> pumpGate(
      WidgetTester tester, {
      required bool startLocked,
    }) async {
      final seed = _controller(database);
      final key = seed.setPin('4821')!;
      seed.dispose();
      final lock = _controller(database);
      controllers.add(lock);
      if (!startLocked) lock.unlock('4821');
      addTearDown(() => key);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppLockScope(
            controller: lock,
            child: AppLockGate(controller: lock, child: child!),
          ),
          home: const Scaffold(
            body: Column(
              children: [
                Text('Secret inventory'),
                TextField(key: Key('secret-field')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      return lock;
    }

    testWidgets('hides the app, keeps its state, and unlocks with the PIN', (
      tester,
    ) async {
      final lock = await pumpGate(tester, startLocked: true);

      expect(find.text('Inventorinator is locked'), findsOneWidget);
      expect(find.text('Secret inventory'), findsNothing);
      expect(find.byKey(const Key('secret-field')), findsNothing);
      // Still mounted underneath, so nothing is lost when it unlocks.
      expect(
        find.text('Secret inventory', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Unlock with PIN'), findsWidgets);

      await tester.tap(find.byKey(const Key('unlock-with-pin')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unlock-pin-field')), '0000');
      await tester.tap(find.byKey(const Key('unlock-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-lock-error')), findsOneWidget);
      expect(find.text('Incorrect PIN.'), findsOneWidget);
      expect(lock.locked, isTrue);

      await tester.enterText(find.byKey(const Key('unlock-pin-field')), '4821');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(lock.locked, isFalse);
      expect(find.text('Inventorinator is locked'), findsNothing);
      expect(find.text('Secret inventory'), findsOneWidget);
    });

    testWidgets('the top-right lock icon also starts unlocking', (
      tester,
    ) async {
      await pumpGate(tester, startLocked: true);

      await tester.tap(find.byKey(const Key('app-unlock-icon')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unlock-pin-field')), findsOneWidget);
    });

    testWidgets(
      'locking hides an app that was open, and unlocking restores it',
      (tester) async {
        final lock = await pumpGate(tester, startLocked: false);
        await tester.enterText(
          find.byKey(const Key('secret-field')),
          'half typed',
        );
        expect(find.text('Secret inventory'), findsOneWidget);

        lock.lock();
        await tester.pumpAndSettle();
        expect(find.text('Secret inventory'), findsNothing);
        expect(find.text('Inventorinator is locked'), findsOneWidget);

        lock.unlock('4821');
        await tester.pumpAndSettle();
        expect(find.text('half typed'), findsOneWidget);
      },
    );

    testWidgets('forgot PIN: key, new PIN, save the new key, then open', (
      tester,
    ) async {
      final seed = _controller(database);
      final oldKey = seed.setPin('4821')!;
      seed.dispose();
      final lock = _controller(database);
      controllers.add(lock);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppLockGate(controller: lock, child: child!),
          home: const Scaffold(body: Text('Secret inventory')),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forgot-pin')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unlock-key-field')), 'nope');
      await tester.tap(find.byKey(const Key('unlock-key-submit')));
      await tester.pumpAndSettle();
      expect(find.text('That unlock key is not correct.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('unlock-key-field')), oldKey);
      await tester.tap(find.byKey(const Key('unlock-key-submit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reset-new-pin')), '2468');
      await tester.enterText(
        find.byKey(const Key('reset-confirm-pin')),
        '2469',
      );
      await tester.tap(find.byKey(const Key('reset-set-pin')));
      await tester.pumpAndSettle();
      expect(find.text('The two PINs do not match.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reset-confirm-pin')),
        '2468',
      );
      await tester.tap(find.byKey(const Key('reset-set-pin')));
      await tester.pumpAndSettle();

      // The new key must be acknowledged before the app opens.
      final newKey = tester
          .widget<SelectableText>(find.byKey(const Key('unlock-key-value')))
          .data!;
      expect(newKey, isNot(oldKey));
      expect(lock.locked, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('unlock-key-done')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('unlock-key-saved')));
      await tester.tap(find.byKey(const Key('unlock-key-saved')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('unlock-key-done')));
      await tester.tap(find.byKey(const Key('unlock-key-done')));
      await tester.pumpAndSettle();

      expect(lock.locked, isFalse);
      expect(find.text('Secret inventory'), findsOneWidget);
      expect(lock.checkUnlockKey(newKey), AppLockResult.success);
    });
  });

  group('whole app', () {
    Future<LocalDatabase> open(WidgetTester tester) async {
      final db = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${directory.path}/app.sqlite3'),
      ))!;
      return db;
    }

    String state() => encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );

    testWidgets('without a PIN there is no lock button and nothing is locked', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await open(tester);
      await tester.pumpWidget(
        InventorinatorApp(database: db, persistedState: state()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock')), findsNothing);
      expect(find.text('Inventorinator is locked'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      db.close();
    });

    testWidgets('a PIN adds the lock button, which locks and unlocks the app', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await open(tester);
      final seed = _controller(db);
      seed.setPin('4821');
      seed.dispose();
      await tester.pumpWidget(
        InventorinatorApp(database: db, persistedState: state()),
      );
      await tester.pumpAndSettle();

      // A set PIN is asked for once at startup.
      expect(find.text('Inventorinator is locked'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unlock-with-pin')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unlock-pin-field')), '4821');
      await tester.tap(find.byKey(const Key('unlock-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Inventorinator is locked'), findsNothing);

      // Then the lock button at the top right locks it again.
      expect(find.byKey(const Key('app-lock')), findsOneWidget);
      // Header buttons are pressed directly, as the other widget tests do.
      tester.widget<IconButton>(find.byKey(const Key('app-lock'))).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Inventorinator is locked'), findsOneWidget);
      expect(find.byKey(const Key('cloud-sync')), findsNothing);
      expect(find.byKey(const Key('database-settings')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      db.close();
    });

    testWidgets(
      'a PIN can be set from settings and shows the unlock key once',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = await open(tester);
        await tester.pumpWidget(
          InventorinatorApp(database: db, persistedState: state()),
        );
        await tester.pumpAndSettle();

        tester
            .widget<IconButton>(
              find.byKey(const Key('personalization-settings')),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('app-lock-settings')), findsOneWidget);
        await tester.tap(find.byKey(const Key('set-app-pin')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('pin-new')), '4821');
        await tester.enterText(find.byKey(const Key('pin-confirm')), '4821');
        await tester.tap(find.byKey(const Key('pin-dialog-submit')));
        await tester.pumpAndSettle();

        expect(find.text('Save your unlock key'), findsOneWidget);
        final key = tester
            .widget<SelectableText>(find.byKey(const Key('unlock-key-value')))
            .data!;
        expect(key, isNotEmpty);
        await tester.tap(find.byKey(const Key('unlock-key-saved')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('unlock-key-done')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('change-app-pin')), findsOneWidget);
        expect(find.byKey(const Key('app-lock-timeout')), findsOneWidget);
        expect(
          db.loadStringPreference('app_lock_pin_hash', fallback: ''),
          isNotEmpty,
        );

        await tester.pumpWidget(const SizedBox());
        db.close();
      },
    );
  });
}

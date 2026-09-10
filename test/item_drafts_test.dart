import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/item_drafts.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';

void main() {
  test(
    'drafts persist separately from inventory and isolate workspaces',
    () async {
      final dir = Directory.systemTemp.createTempSync('item-drafts-');
      final path = '${dir.path}/test.sqlite3';
      var db = await LocalDatabase.open(overridePath: path);
      final store = ItemDraftStore(db, 'local');
      final id = store.save(null, {
        'fields': {'quantity': '12.'},
        'photo': 'bytes',
      }, title: '');
      store.save(null, {'edit': true}, itemId: 'existing', title: 'Edit');
      expect(store.list().single['title'], 'Untitled item');
      expect(store.list().single.containsKey('photo'), false);
      expect(ItemDraftStore(db, 'other').list(), isEmpty);
      expect(db.loadState(), isNull);
      db.close();
      db = await LocalDatabase.open(overridePath: path);
      final reopened = ItemDraftStore(db, 'local');
      expect(reopened.load(id)!['fields'], {'quantity': '12.'});
      reopened.delete(id);
      expect(reopened.list(), isEmpty);
      expect(reopened.load(id), isNull);
      expect(reopened.list(itemId: 'existing'), hasLength(1));
      db.close();
      dir.deleteSync(recursive: true);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('draft controls fit Android at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('draft-phone-');
      final db = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${dir.path}/test.sqlite3'),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: AddItemDialog(database: db)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-item')).hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('save-item-draft')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('item-drafts')));
      await tester.pumpAndSettle();
      expect(find.text('Start new').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      db.close();
      dir.deleteSync(recursive: true);
    });
  }

  testWidgets('close, resume, choose, start new and save incomplete drafts', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('item-draft-ui-');
    final db = (await tester.runAsync(
      () => LocalDatabase.open(overridePath: '${dir.path}/test.sqlite3'),
    ))!;
    final store = ItemDraftStore(db, 'local');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AddItemDialog(database: db),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }

    dynamic editor() => tester.state(find.byType(AddItemDialog));
    await open();
    await close();
    expect(store.list(), isEmpty);
    await open();
    editor().nameController.text = 'First draft';
    editor().quantityController.text = '12.';
    await tester.tap(find.byKey(const Key('save-item-draft')));
    await tester.pumpAndSettle();
    expect(find.byType(AddItemDialog), findsNothing);
    expect(store.list(), hasLength(1));
    expect(db.loadState(), isNull);
    await open();
    expect(editor().nameController.text, 'First draft');
    expect(editor().quantityController.text, '12.');
    await tester.tap(find.byKey(const Key('item-drafts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start new'));
    await tester.pumpAndSettle();
    expect(editor().nameController.text, '');
    editor().nameController.text = 'Second draft';
    await close();
    expect(store.list(), hasLength(2));
    await open();
    expect(editor().nameController.text, 'Second draft');
    await close();
    db.saveBoolPreference(resumeLatestItemDraftPreference, false);
    await open();
    expect(editor().nameController.text, '');
    await tester.tap(find.byKey(const Key('item-drafts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First draft'));
    await tester.pumpAndSettle();
    expect(editor().quantityController.text, '12.');
    editor().quantityController.text = '1';
    editor().costController.text = '0';
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    expect(find.byType(AddItemDialog), findsNothing);
    expect(store.list().single['title'], 'Second draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    db.close();
    dir.deleteSync(recursive: true);
  });
}

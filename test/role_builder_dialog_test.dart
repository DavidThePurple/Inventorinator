import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/role_builder_dialog.dart';
import 'package:inventorinator/workspace_role_template.dart';

void main() {
  testWidgets('owner can name a preset and save its selected permissions', (
    tester,
  ) async {
    WorkspaceRoleTemplate? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleTemplateEditor(
            save: (template) async {
              saved = template;
            },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('role-template-name')),
      'Stock assistant',
    );
    await tester.tap(find.text('Inventory editor'));
    await tester.tap(find.byKey(const Key('save-role-template')));
    await tester.pumpAndSettle();
    expect(saved?.name, 'Stock assistant');
    expect(saved?.permissions, RoleTemplatePreset.editor.permissions);
    expect(saved?.id, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rejection keeps the editor and entered name available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleTemplateEditor(
            save: (_) async =>
                throw Exception('Only the owner can manage role templates'),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('role-template-name')),
      'Reader',
    );
    await tester.tap(find.byKey(const Key('save-role-template')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the owner'), findsOneWidget);
    expect(find.text('Reader'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('builder and editor fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleBuilderDialog(
            load: () async => [],
            save: (_) async {},
            delete: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-role-template')));
    await tester.pumpAndSettle();
    expect(find.text('New role template'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

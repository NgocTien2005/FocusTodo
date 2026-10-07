import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/app.dart';
import 'package:focus_todo/controllers/todo_controller.dart';

void main() {
  testWidgets('starter displays controls and switches all categories', (
    tester,
  ) async {
    await tester.pumpWidget(const FocusTodoApp());
    expect(find.text('FocusTodo'), findsOneWidget);
    expect(find.text('Search TODOs'), findsOneWidget);
    expect(find.text('Add TODO'), findsOneWidget);
    expect(
      find.text('Coming next: create TODOs and set reminders.'),
      findsOneWidget,
    );

    SegmentedButton<TodoCategory> selector() =>
        tester.widget<SegmentedButton<TodoCategory>>(
          find.byType(SegmentedButton<TodoCategory>),
        );
    expect(selector().selected, {TodoCategory.all});
    for (final entry in {
      'Today': TodoCategory.today,
      'Upcoming': TodoCategory.upcoming,
      'All': TodoCategory.all,
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(selector().selected, {entry.value});
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('unfinished actions disclose coming next', (tester) async {
    await tester.pumpWidget(const FocusTodoApp());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Coming next: search TODOs.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add TODO'));
    await tester.pumpAndSettle();
    expect(
      find.text('Coming next: add a TODO with a date and time.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

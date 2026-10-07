import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/app.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';

import 'support/memory_document_store.dart';

final _now = DateTime(2026, 10, 7, 12);
const _titleKey = Key('todo-title');
const _descriptionKey = Key('todo-description');
const _saveKey = Key('save-todo');

Future<void> _home(
  WidgetTester tester,
  MemoryDocumentStore store, {
  TodoClock? clock,
}) async {
  await tester.pumpWidget(
    FocusTodoApp(
      repository: SharedPreferencesTodoRepository(store: store),
      clock: clock ?? () => _now,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('Add TODO'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_saveKey));
  await tester.tap(find.byKey(_saveKey));
  await tester.pumpAndSettle();
}

Future<void> _date(WidgetTester tester, String day) async {
  await tester.ensureVisible(find.byKey(const Key('pick-date')));
  await tester.tap(find.byKey(const Key('pick-date')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(day).last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _time(WidgetTester tester, String hour, String minute) async {
  await tester.ensureVisible(find.byKey(const Key('pick-time')));
  await tester.tap(find.byKey(const Key('pick-time')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), hour);
  await tester.enterText(fields.at(1), minute);
  if (find.text('AM').evaluate().isNotEmpty) {
    await tester.tap(find.text('AM').last);
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home switches categories and keeps Search explicitly pending', (
    tester,
  ) async {
    await _home(tester, MemoryDocumentStore());
    expect(find.text('FocusTodo'), findsOneWidget);
    expect(
      find.text('No active TODOs. Add one to get started.'),
      findsOneWidget,
    );
    for (final entry in {
      'Today': TodoCategory.today,
      'Upcoming': TodoCategory.upcoming,
      'All': TodoCategory.all,
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<TodoCategory>>(
              find.byType(SegmentedButton<TodoCategory>),
            )
            .selected,
        {entry.value},
      );
    }
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Coming next: search TODOs.'), findsOneWidget);
  });

  testWidgets(
    'successful undated creation appears on Home and after fresh startup',
    (tester) async {
      final store = MemoryDocumentStore();
      await _home(tester, store);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), '  Read notes  ');
      await tester.enterText(find.byKey(_descriptionKey), '  Chapter 1  ');
      await _save(tester);
      expect(find.text('Create TODO'), findsNothing);
      expect(find.text('Read notes'), findsOneWidget);
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('No due date or time'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _home(tester, store);
      expect(find.text('Read notes'), findsOneWidget);
    },
  );

  testWidgets(
    'dated creation uses pickers and appears only in the matching category',
    (tester) async {
      final store = MemoryDocumentStore();
      await _home(tester, store);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Tomorrow task');
      await _date(tester, '8');
      await _time(tester, '10', '30');
      await _save(tester);
      expect(find.text('Tomorrow task'), findsOneWidget);
      final todo = (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single;
      expect(
        todo.dueAt!.isAtSameMomentAs(DateTime(2026, 10, 8, 10, 30)),
        isTrue,
      );
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow task'), findsNothing);
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow task'), findsOneWidget);
    },
  );

  testWidgets(
    'form validates blank title, incomplete date/time and past combined time; clearing is supported',
    (tester) async {
      final store = MemoryDocumentStore();
      await _home(tester, store);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), '   ');
      await _save(tester);
      expect(find.text('Enter a title.'), findsOneWidget);
      await tester.enterText(find.byKey(_titleKey), 'Valid');
      await _date(tester, '7');
      await _save(tester);
      expect(
        find.text('Choose both a date and a time, or clear the due time.'),
        findsOneWidget,
      );
      await _time(tester, '9', '00');
      await _save(tester);
      expect(
        find.text('Choose a due date and time in the future.'),
        findsOneWidget,
      );
      expect(store.writes, 0);
      await tester.ensureVisible(find.text('Clear due time'));
      await tester.tap(find.text('Clear due time'));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(find.text('Valid'), findsOneWidget);
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).single.dueAt,
        isNull,
      );
    },
  );

  testWidgets(
    'storage failure retains entered form data and retry saves once',
    (tester) async {
      final store = MemoryDocumentStore()..rejectWrite = true;
      await _home(tester, store);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Keep this title');
      await tester.enterText(find.byKey(_descriptionKey), 'Keep these notes');
      await _date(tester, '8');
      await _time(tester, '10', '30');
      await _save(tester);
      expect(find.byKey(const Key('save-error')), findsOneWidget);
      expect(find.text('Create TODO'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byKey(_titleKey)).controller!.text,
        'Keep this title',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(_descriptionKey))
            .controller!
            .text,
        'Keep these notes',
      );
      expect(find.text('Oct 8, 2026'), findsOneWidget);
      expect(find.text('10:30 AM'), findsOneWidget);
      expect(store.document, isNull);
      store.rejectWrite = false;
      await _save(tester);
      expect(find.text('Keep this title'), findsOneWidget);
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).length,
        1,
      );
    },
  );

  testWidgets('loading, error and retry protect unreadable data', (
    tester,
  ) async {
    final gate = Completer<void>();
    final store = MemoryDocumentStore()
      ..document = 'corrupt'
      ..readGate = gate;
    await tester.pumpWidget(
      FocusTodoApp(
        repository: SharedPreferencesTodoRepository(store: store),
        clock: () => _now,
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add TODO'))
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not load TODOs'), findsOneWidget);
    expect(store.document, 'corrupt');
    expect(store.writes, 0);
    store.document =
        null; // Recovery performed outside the app, not silent reset.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No active TODOs. Add one to get started.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add TODO'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Save is disabled during an in-flight write and double taps create one item',
    (tester) async {
      final gate = Completer<void>();
      final store = MemoryDocumentStore()..writeGate = gate;
      await _home(tester, store);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Only once');
      await tester.ensureVisible(find.byKey(_saveKey));
      await tester.tap(find.byKey(_saveKey));
      await tester.tap(find.byKey(_saveKey));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
        isNull,
      );
      expect(find.text('Saving…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Only once'), findsOneWidget);
      expect(store.writes, 1);
    },
  );

  testWidgets('small-screen form remains scrollable with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await _home(tester, MemoryDocumentStore());
    await _openForm(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_titleKey), 'Small screen');
    await tester.ensureVisible(find.byKey(_descriptionKey));
    await tester.enterText(find.byKey(_descriptionKey), 'Notes with keyboard');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_saveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveKey).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.text('Small screen'), findsOneWidget);
  });

  testWidgets('resuming recomputes category membership after local midnight', (
    tester,
  ) async {
    var clock = _now;
    final store = MemoryDocumentStore();
    final repository = SharedPreferencesTodoRepository(store: store);
    await repository.saveTodos([
      Todo(
        id: 'today',
        title: 'Old day',
        createdAt: _now,
        dueAt: DateTime(2026, 10, 7, 18).toUtc(),
        notificationId: 0,
      ),
      Todo(
        id: 'tomorrow',
        title: 'New day',
        createdAt: _now,
        dueAt: DateTime(2026, 10, 8).toUtc(),
        notificationId: 1,
      ),
    ]);
    await _home(tester, store, clock: () => clock);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Old day'), findsOneWidget);
    expect(find.text('New day'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = DateTime(2026, 10, 8, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Old day'), findsNothing);
    expect(find.text('New day'), findsOneWidget);
  });
}

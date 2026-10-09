import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/app.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';
import 'package:provider/provider.dart';

import 'support/memory_document_store.dart';

final _now = DateTime(2026, 10, 7, 12);
const _titleKey = Key('todo-title');
const _descriptionKey = Key('todo-description');
const _saveKey = Key('save-todo');
const _searchKey = Key('todo-search');

TodoController _controller(WidgetTester tester) =>
    tester.element(find.byKey(_searchKey)).read<TodoController>();

Future<MemoryDocumentStore> _searchStore() async {
  final store = MemoryDocumentStore();
  await SharedPreferencesTodoRepository(store: store).saveTodos([
    Todo(
      id: 'today',
      title: 'Read today',
      createdAt: _now,
      dueAt: DateTime(2026, 10, 7, 18).toUtc(),
      notificationId: 0,
    ),
    Todo(
      id: 'tomorrow',
      title: 'Read tomorrow',
      createdAt: _now,
      dueAt: DateTime(2026, 10, 8).toUtc(),
      notificationId: 1,
    ),
    Todo(
      id: 'undated',
      title: 'Buy milk',
      description: 'Grocery list',
      createdAt: _now,
      notificationId: 2,
    ),
  ]);
  return store;
}

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
  testWidgets('Home switches categories and offers editable search', (
    tester,
  ) async {
    await _home(tester, MemoryDocumentStore());
    expect(find.text('FocusTodo'), findsOneWidget);
    expect(find.text('No active TODOs.'), findsOneWidget);
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
    await tester.enterText(find.byKey(_searchKey), 'anything');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_searchKey)).readOnly, isFalse);
    expect(_controller(tester).searchQuery, 'anything');
    expect(find.text('No active TODOs.'), findsOneWidget);
    expect(find.text('Coming next: search TODOs.'), findsNothing);
    expect(find.text('Coming next'), findsNothing);
  });

  testWidgets(
    'typing filters title and description while retaining focus and text',
    (tester) async {
      final store = await _searchStore();
      await _home(tester, store);
      final field = tester
          .widget<TextField>(find.byKey(_searchKey))
          .controller!;
      await tester.enterText(find.byKey(_searchKey), '  rEaD  ');
      await tester.pumpAndSettle();
      expect(find.text('Read today'), findsOneWidget);
      expect(find.text('Read tomorrow'), findsOneWidget);
      expect(find.text('Buy milk'), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller,
        same(field),
      );
      expect(field.text, '  rEaD  ');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      final selection = const TextSelection.collapsed(offset: 3);
      field.selection = selection;
      _controller(tester).refreshDateSensitiveResults();
      await tester.pumpAndSettle();
      expect(field.selection, selection);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byKey(_searchKey), 'GROCERY');
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Read today'), findsNothing);
      expect(find.text('Read tomorrow'), findsNothing);
      expect(store.writes, 1); // Fixture setup only.
    },
  );

  testWidgets(
    'clear resets field and query and restores only the selected category',
    (tester) async {
      await _home(tester, await _searchStore());
      await tester.tap(find.text('Today'));
      await tester.enterText(find.byKey(_searchKey), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching TODOs in this category.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        isEmpty,
      );
      expect(_controller(tester).searchQuery, isEmpty);
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(find.text('Read today'), findsOneWidget);
      expect(find.text('Read tomorrow'), findsNothing);
      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('No matching TODOs in this category.'), findsNothing);
    },
  );

  testWidgets(
    'empty messages distinguish category, search and whitespace-only query',
    (tester) async {
      final store = MemoryDocumentStore();
      await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'Undated', createdAt: _now);
      await _home(tester, store);
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('No TODOs in this category.'), findsOneWidget);
      await tester.enterText(find.byKey(_searchKey), 'undated');
      await tester.pumpAndSettle();
      expect(find.text('No matching TODOs in this category.'), findsOneWidget);
      await tester.enterText(find.byKey(_searchKey), '   ');
      await tester.pumpAndSettle();
      expect(find.text('No TODOs in this category.'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Undated'), findsOneWidget);
      await tester.enterText(find.byKey(_searchKey), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching TODOs in this category.'), findsOneWidget);
    },
  );

  testWidgets(
    'switching categories preserves entered query and filters each list',
    (tester) async {
      await _home(tester, await _searchStore());
      await tester.enterText(find.byKey(_searchKey), '  rEaD  ');
      for (final category in ['Today', 'Upcoming', 'All']) {
        await tester.tap(find.text(category));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
          '  rEaD  ',
        );
        expect(_controller(tester).searchQuery, '  rEaD  ');
        expect(
          find.text('Read today'),
          category == 'Upcoming' ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Read tomorrow'),
          category == 'Today' ? findsNothing : findsOneWidget,
        );
        expect(find.text('Buy milk'), findsNothing);
      }
    },
  );

  testWidgets(
    'returning from create without saving preserves query and category',
    (tester) async {
      final store = await _searchStore();
      await _home(tester, store);
      await tester.tap(find.text('Upcoming'));
      await tester.enterText(find.byKey(_searchKey), 'read');
      await tester.pumpAndSettle();
      await _openForm(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        'read',
      );
      expect(_controller(tester).searchQuery, 'read');
      expect(_controller(tester).category, TodoCategory.upcoming);
      expect(find.text('Read tomorrow'), findsOneWidget);
      expect(find.text('Read today'), findsNothing);
      expect(store.writes, 1);
    },
  );

  testWidgets(
    'created matching TODO appears, nonmatching stays hidden, restart clears query',
    (tester) async {
      final store = MemoryDocumentStore();
      await _home(tester, store);
      await tester.enterText(find.byKey(_searchKey), 'read');
      await tester.pumpAndSettle();
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'New task');
      await tester.enterText(find.byKey(_descriptionKey), 'Read a chapter');
      await _save(tester);
      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Read a chapter'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        'read',
      );
      expect(_controller(tester).searchQuery, 'read');
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Buy supplies');
      await _save(tester);
      expect(find.text('Buy supplies'), findsNothing);
      expect(find.text('New task'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        'read',
      );
      expect(_controller(tester).searchQuery, 'read');
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).map((todo) => todo.title),
        ['New task', 'Buy supplies'],
      );
      expect(store.writes, 2);
      await tester.pumpWidget(const SizedBox());
      await _home(tester, store);
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
        isEmpty,
      );
      expect(_controller(tester).searchQuery, isEmpty);
      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Buy supplies'), findsOneWidget);
    },
  );

  testWidgets('dragging the TODO list dismisses the search keyboard', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    await SharedPreferencesTodoRepository(store: store).saveTodos([
      for (var i = 0; i < 20; i++)
        Todo(
          id: 'item-$i',
          title: 'Read $i',
          createdAt: _now,
          notificationId: i,
        ),
    ]);
    await _home(tester, store);
    await tester.enterText(find.byKey(_searchKey), 'read');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
      'read',
    );
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
    expect(find.text('No active TODOs.'), findsOneWidget);
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

  testWidgets(
    'completion shows pending progress then removes the last active TODO',
    (tester) async {
      final store = MemoryDocumentStore();
      await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'Finish me', createdAt: _now);
      await _home(tester, store);
      final checkbox = find.byKey(const ValueKey('complete-todo-1'));
      expect(checkbox, findsOneWidget);
      store.writeGate = Completer<void>();
      await tester.tap(checkbox);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Finish me'), findsNothing);
      expect(find.text('No active TODOs.'), findsOneWidget);
      expect(find.text('Completed “Finish me”.'), findsOneWidget);
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).single.isCompleted,
        isTrue,
      );
    },
  );

  testWidgets('completion failure retains the item and can be retried', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    await SharedPreferencesTodoRepository(store: store)
        .createTodo(title: 'Retry me', createdAt: _now);
    await _home(tester, store);
    store.rejectWrite = true;
    await tester.tap(find.byKey(const ValueKey('complete-todo-1')));
    await tester.pumpAndSettle();
    expect(find.text('Retry me'), findsOneWidget);
    expect(find.textContaining('Could not complete TODO'), findsOneWidget);
    store.rejectWrite = false;
    await tester.tap(find.byKey(const ValueKey('complete-todo-1')));
    await tester.pumpAndSettle();
    expect(find.text('Retry me'), findsNothing);
  });
}

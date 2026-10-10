import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/app.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';
import 'package:focus_todo/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'support/memory_document_store.dart';
import 'support/memory_notification_service.dart';

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
  MemoryNotificationService? notifications,
}) async {
  await tester.pumpWidget(
    FocusTodoApp(
      repository: SharedPreferencesTodoRepository(store: store),
      notificationService: notifications ?? MemoryNotificationService()
        ..now = _now,
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

Future<void> _time(
  WidgetTester tester,
  String hour,
  String minute, {
  String period = 'AM',
}) async {
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
  if (find.text(period).evaluate().isNotEmpty) {
    await tester.tap(find.text(period).last);
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
        notificationService: MemoryNotificationService()..now = _now,
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

  testWidgets('edit prepopulates fields and preserves category and query', (
    tester,
  ) async {
    final store = await _searchStore();
    final notifications = MemoryNotificationService()..now = _now;
    await _home(tester, store, notifications: notifications);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_searchKey), 'read');
    await tester.pumpAndSettle();
    expect(find.text('Read today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('edit-today')));
    await tester.pumpAndSettle();
    expect(find.text('Edit TODO'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(_titleKey)).controller!.text,
      'Read today',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(_descriptionKey))
          .controller!
          .text,
      '',
    );
    final storedDue = DateTime(2026, 10, 7, 18).toUtc().toLocal();
    expect(find.text(DateFormat.yMMMd().format(storedDue)), findsOneWidget);
    expect(find.text('Choose time'), findsNothing);
    expect(storedDue.hour, 18);
    await tester.enterText(find.byKey(_titleKey), 'Edited today');
    await tester.ensureVisible(find.byKey(_saveKey));
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();

    expect(_controller(tester).category, TodoCategory.today);
    expect(_controller(tester).searchQuery, 'read');
    expect(find.text('No matching TODOs in this category.'), findsOneWidget);
    final edited = (await SharedPreferencesTodoRepository(
      store: store,
    ).loadTodos()).first;
    expect(edited.title, 'Edited today');
    expect(notifications.cancelledIds, [edited.notificationId]);
    expect(notifications.scheduledTodos.last.title, 'Edited today');
    await tester.enterText(find.byKey(_searchKey), 'edited');
    await tester.pumpAndSettle();
    expect(find.text('Edited today'), findsOneWidget);
  });

  testWidgets(
    'edit failure retains input and leaves original record unchanged',
    (tester) async {
      final store = MemoryDocumentStore();
      final original = await SharedPreferencesTodoRepository(store: store)
          .createTodo(
            title: 'Original title',
            description: 'Original description',
            createdAt: _now,
          );
      await _home(tester, store);
      await tester.tap(find.byKey(ValueKey('edit-${original.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_titleKey), 'Attempted edit');
      store.rejectWrite = true;
      await tester.ensureVisible(find.byKey(_saveKey));
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-error')), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byKey(_titleKey)).controller!.text,
        'Attempted edit',
      );
      final unchanged = (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single;
      expect(unchanged.toJson(), original.toJson());

      store.rejectWrite = false;
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();
      expect(find.text('FocusTodo'), findsOneWidget);
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).single.title,
        'Attempted edit',
      );
    },
  );

  testWidgets('canceling an edit leaves saved TODO unchanged', (tester) async {
    final store = MemoryDocumentStore();
    final original = await SharedPreferencesTodoRepository(store: store)
        .createTodo(title: 'Leave unchanged', createdAt: _now);
    await _home(tester, store);
    await tester.tap(find.byKey(ValueKey('edit-${original.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_titleKey), 'Unsaved title');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single.toJson(),
      original.toJson(),
    );
    expect(find.text('Leave unchanged'), findsOneWidget);
  });

  testWidgets('edit reminder cancellation warning has a retry action', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    final todo = await SharedPreferencesTodoRepository(store: store).createTodo(
      title: 'Reminder before edit',
      dueAt: _now.add(const Duration(hours: 1)),
      createdAt: _now,
    );
    final notifications = MemoryNotificationService()..now = _now;
    await _home(tester, store, notifications: notifications);
    notifications.failCancel = true;
    await tester.tap(find.byKey(ValueKey('edit-${todo.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_titleKey), 'Reminder after edit');
    await tester.ensureVisible(find.byKey(_saveKey));
    await tester.tap(find.byKey(_saveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reminder-update-warning')), findsOneWidget);
    expect(
      (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single.title,
      'Reminder after edit',
    );
    notifications.failCancel = false;
    await tester.tap(find.byKey(const Key('retry-reminder')));
    await tester.pumpAndSettle();

    expect(find.text('FocusTodo'), findsOneWidget);
    expect(notifications.pending[todo.notificationId]?.payload, todo.id);
    expect(notifications.scheduledTodos.last.title, 'Reminder after edit');
    expect(
      notifications.scheduledTodos.last.notificationId,
      todo.notificationId,
    );
  });

  testWidgets(
    'editing an overdue TODO without changing its due time succeeds',
    (tester) async {
      final store = MemoryDocumentStore();
      final repository = SharedPreferencesTodoRepository(store: store);
      final overdue = await repository.createTodo(
        title: 'Overdue item',
        dueAt: _now.subtract(const Duration(days: 1)),
        createdAt: _now.subtract(const Duration(days: 2)),
      );
      await _home(tester, store);
      await tester.tap(find.byKey(ValueKey('edit-${overdue.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_titleKey), 'Updated overdue title');
      await tester.ensureVisible(find.byKey(_saveKey));
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();

      final saved = (await repository.loadTodos()).single;
      expect(saved.title, 'Updated overdue title');
      expect(saved.dueAt!.isAtSameMomentAs(overdue.dueAt!), isTrue);
    },
  );

  testWidgets('selecting a past due time in edit is rejected at submission', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    final original = await SharedPreferencesTodoRepository(store: store)
        .createTodo(
          title: 'Future today',
          dueAt: DateTime(2026, 10, 7, 18).toUtc(),
          createdAt: _now,
        );
    await _home(tester, store);
    await tester.tap(find.byKey(ValueKey('edit-${original.id}')));
    await tester.pumpAndSettle();
    await _time(tester, '11', '00', period: 'AM');
    await _save(tester);

    expect(find.byKey(const Key('due-error')), findsOneWidget);
    expect(find.text('Edit TODO'), findsOneWidget);
    expect(
      (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single.toJson(),
      original.toJson(),
    );
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

  testWidgets('Enable reminders requests permissions and reconciles TODOs', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    final todo = await SharedPreferencesTodoRepository(store: store).createTodo(
      title: 'Permission reminder',
      dueAt: _now.add(const Duration(hours: 1)),
      createdAt: _now,
    );
    final notifications = MemoryNotificationService()
      ..now = _now
      ..permissionStatus = ReminderPermissionStatus.notificationsDenied
      ..requestedStatus = ReminderPermissionStatus.enabled;
    await _home(tester, store, notifications: notifications);
    expect(
      find.text(
        'Notifications are disabled. Enable them to receive TODO reminders.',
      ),
      findsOneWidget,
    );
    expect(notifications.pending, isEmpty);
    await tester.tap(find.text('Enable reminders'));
    await tester.pumpAndSettle();
    expect(notifications.permissionRequests, 1);
    expect(notifications.pending[todo.notificationId]?.payload, todo.id);
    expect(find.text('Enable reminders'), findsNothing);
  });

  testWidgets(
    'initialization failure leaves TODOs visible and can be retried',
    (tester) async {
      final store = MemoryDocumentStore();
      await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'Still manageable', createdAt: _now);
      final notifications = MemoryNotificationService()
        ..now = _now
        ..failInitialize = true;
      await _home(tester, store, notifications: notifications);
      expect(find.text('Still manageable'), findsOneWidget);
      expect(find.text('Reminders could not be initialized.'), findsOneWidget);
      notifications.failInitialize = false;
      await tester.tap(find.text('Retry reminders'));
      await tester.pumpAndSettle();
      expect(find.text('Reminders could not be initialized.'), findsNothing);
      expect(find.text('Still manageable'), findsOneWidget);
    },
  );

  testWidgets(
    'saved TODO reminder failure is retryable without duplicate creation',
    (tester) async {
      final store = MemoryDocumentStore();
      final notifications = MemoryNotificationService()
        ..now = _now
        ..failSchedule = true;
      await _home(tester, store, notifications: notifications);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Retry scheduled reminder');
      await _date(tester, '7');
      await _time(tester, '1', '30', period: 'PM');
      await _save(tester);
      expect(
        find.text('TODO saved, but reminder could not be scheduled.'),
        findsOneWidget,
      );
      expect(store.writes, 1);
      final saved = (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single;
      notifications.failSchedule = false;
      await tester.ensureVisible(find.byKey(const Key('retry-reminder')));
      await tester.tap(find.byKey(const Key('retry-reminder')));
      await tester.pumpAndSettle();
      expect(find.text('FocusTodo'), findsOneWidget);
      expect(store.writes, 1);
      expect(notifications.scheduledTodos.map((todo) => todo.notificationId), [
        saved.notificationId,
        saved.notificationId,
      ]);
      expect(notifications.pending[saved.notificationId]?.payload, saved.id);
    },
  );

  testWidgets(
    'TODO due in under ten minutes is saved without an immediate reminder',
    (tester) async {
      final store = MemoryDocumentStore();
      final notifications = MemoryNotificationService()..now = _now;
      await _home(tester, store, notifications: notifications);
      await _openForm(tester);
      await tester.enterText(find.byKey(_titleKey), 'Due very soon');
      await _date(tester, '7');
      await _time(tester, '12', '05', period: 'PM');
      await _save(tester);
      expect(find.byKey(const Key('no-advance-reminder')), findsOneWidget);
      expect(store.writes, 1);
      expect(notifications.scheduledTodos, isEmpty);
      expect(
        await SharedPreferencesTodoRepository(store: store).loadTodos(),
        hasLength(1),
      );
    },
  );

  testWidgets('cancellation warning stays on Home and retry clears it', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    final todo = await SharedPreferencesTodoRepository(store: store).createTodo(
      title: 'Cancel reminder',
      dueAt: _now.add(const Duration(hours: 1)),
      createdAt: _now,
    );
    final notifications = MemoryNotificationService()..now = _now;
    await _home(tester, store, notifications: notifications);
    notifications.failCancel = true;
    await tester.tap(find.byKey(const ValueKey('complete-todo-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not cancel reminder for Cancel reminder.'),
      findsOneWidget,
    );
    expect(
      (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single.isCompleted,
      isTrue,
    );
    notifications.failCancel = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(notifications.cancelledIds, [
      todo.notificationId,
      todo.notificationId,
    ]);
    expect(_controller(tester).reminderCancellationWarnings, isEmpty);
    expect(notifications.pending.containsKey(todo.notificationId), isFalse);
    expect(
      find.text('Could not cancel reminder for Cancel reminder.'),
      findsNothing,
    );
  });

  testWidgets('delete confirmation cancel leaves TODO unchanged', (
    tester,
  ) async {
    final store = MemoryDocumentStore();
    await SharedPreferencesTodoRepository(store: store)
        .createTodo(title: 'Buy milk', createdAt: _now);
    await _home(tester, store);
    await tester.tap(find.byKey(const ValueKey('delete-todo-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete “Buy milk”? This cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('cancel-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(
      (await SharedPreferencesTodoRepository(store: store).loadTodos()),
      hasLength(1),
    );
  });

  testWidgets(
    'confirmed deletion removes last visible item and cancels reminder',
    (tester) async {
      final store = MemoryDocumentStore();
      final notifications = MemoryNotificationService()..now = _now;
      await SharedPreferencesTodoRepository(store: store).createTodo(
        title: 'Last visible',
        dueAt: _now.add(const Duration(hours: 1)),
        createdAt: _now,
      );
      await _home(tester, store, notifications: notifications);
      await tester.tap(find.byKey(const ValueKey('delete-todo-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.text('No active TODOs.'), findsOneWidget);
      expect(
        await SharedPreferencesTodoRepository(store: store).loadTodos(),
        isEmpty,
      );
      expect(notifications.cancelledIds, [0]);
    },
  );

  testWidgets('failed delete retains TODO and allows retry', (tester) async {
    final store = MemoryDocumentStore();
    await SharedPreferencesTodoRepository(store: store)
        .createTodo(title: 'Buy milk', createdAt: _now);
    await _home(tester, store);
    store.rejectWrite = true;
    await tester.tap(find.byKey(const ValueKey('delete-todo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.textContaining('Could not delete TODO'), findsOneWidget);
    expect(
      await SharedPreferencesTodoRepository(store: store).loadTodos(),
      hasLength(1),
    );
    store.rejectWrite = false;
    await tester.tap(find.byKey(const ValueKey('delete-todo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsNothing);
    expect(
      await SharedPreferencesTodoRepository(store: store).loadTodos(),
      isEmpty,
    );
  });
}

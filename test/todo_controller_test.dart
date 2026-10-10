import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';
import 'package:focus_todo/services/notification_service.dart';

import 'support/memory_document_store.dart';
import 'support/memory_notification_service.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);
  late MemoryDocumentStore store;
  late MemoryNotificationService notifications;
  late TodoController controller;
  setUp(() {
    store = MemoryDocumentStore();
    notifications = MemoryNotificationService()..now = now;
    controller = TodoController(
      repository: SharedPreferencesTodoRepository(store: store),
      notificationService: notifications,
      clock: () => now,
    );
  });
  tearDown(() => controller.dispose());

  group('search', () {
    late SharedPreferencesTodoRepository repository;

    setUp(() async {
      repository = SharedPreferencesTodoRepository(store: store);
      Todo item(
        int id,
        String title, {
        String? description,
        DateTime? due,
        bool completed = false,
      }) => Todo(
        id: 'search-$id',
        title: title,
        description: description,
        dueAt: due?.toUtc(),
        createdAt: now.toUtc(),
        notificationId: id,
        isCompleted: completed,
      );

      await repository.saveTodos([
        item(0, 'Read Flutter'),
        item(1, 'Buy milk', description: 'Grocery list', due: now),
        item(
          2,
          'Submit draft',
          description: 'Read review notes',
          due: DateTime(2026, 10, 8, 15),
        ),
        item(3, 'Read yesterday', due: DateTime(2026, 10, 6, 23, 59)),
        item(4, 'Read midnight today', due: DateTime(2026, 10, 7)),
        item(5, 'Read tomorrow', due: DateTime(2026, 10, 8)),
        item(6, 'Read completed', due: now, completed: true),
        item(7, 'Literal [a.*] notes'),
      ]);
      await controller.loadTodos();
    });

    List<String> titles() =>
        controller.visibleTodos.map((todo) => todo.title).toList();

    test('matches a substring of the title', () {
      controller.setSearchQuery('Flutt');
      expect(titles(), ['Read Flutter']);
    });

    test('matches descriptions and safely skips null descriptions', () {
      controller.setSearchQuery('review');
      expect(titles(), ['Submit draft']);
      controller.setSearchQuery('grocery');
      expect(titles(), ['Buy milk']);
    });

    test('ignores case in both title and description', () {
      controller.setSearchQuery('rEaD');
      expect(titles(), [
        'Read Flutter',
        'Submit draft',
        'Read yesterday',
        'Read midnight today',
        'Read tomorrow',
      ]);
    });

    test('ignores surrounding whitespace and retains entered query', () {
      controller.setSearchQuery(' \t ReViEw \n ');
      expect(titles(), ['Submit draft']);
      expect(controller.searchQuery, ' \t ReViEw \n ');
      expect(controller.hasSearchQuery, isTrue);
    });

    test('empty and whitespace-only queries restore the selected category', () {
      controller.selectCategory(TodoCategory.today);
      controller.setSearchQuery('read');
      expect(titles(), ['Read midnight today']);
      for (final query in ['', ' \n\t ']) {
        controller.setSearchQuery(query);
        expect(controller.hasSearchQuery, isFalse);
        expect(titles(), ['Buy milk', 'Read midnight today']);
        controller.setSearchQuery('read');
      }
    });

    test(
      'unmatched query returns an empty list without changing active items',
      () {
        controller.setSearchQuery('not present');
        expect(controller.visibleTodos, isEmpty);
        expect(controller.activeTodos, hasLength(7));
      },
    );

    test('regular expression characters are literal substrings', () {
      controller.setSearchQuery('[a.*]');
      expect(titles(), ['Literal [a.*] notes']);
      controller.setSearchQuery('^Read');
      expect(controller.visibleTodos, isEmpty);
    });

    for (final entry in {
      TodoCategory.all: [
        'Read Flutter',
        'Submit draft',
        'Read yesterday',
        'Read midnight today',
        'Read tomorrow',
      ],
      TodoCategory.today: ['Read midnight today'],
      TodoCategory.upcoming: ['Submit draft', 'Read tomorrow'],
    }.entries) {
      test('composes with ${entry.key.name} and excludes completed items', () {
        controller.selectCategory(entry.key);
        controller.setSearchQuery('read');
        expect(titles(), entry.value);
      });
    }

    test('changing categories retains the query and original order', () {
      controller.setSearchQuery('  rEaD  ');
      controller.selectCategory(TodoCategory.upcoming);
      expect(titles(), ['Submit draft', 'Read tomorrow']);
      controller.selectCategory(TodoCategory.today);
      expect(titles(), ['Read midnight today']);
      controller.selectCategory(TodoCategory.all);
      expect(titles().first, 'Read Flutter');
      expect(titles().last, 'Read tomorrow');
      expect(controller.searchQuery, '  rEaD  ');
    });

    test(
      'search never writes or mutates stored TODOs and resets on restart',
      () async {
        final document = store.document;
        final writes = store.writes;
        final original = controller.activeTodos;
        for (final query in ['read', 'missing', '  ', '']) {
          controller.setSearchQuery(query);
          controller.selectCategory(TodoCategory.upcoming);
          controller.visibleTodos;
        }
        expect(store.writes, writes);
        expect(store.document, document);
        expect(controller.activeTodos, original);
        controller.setSearchQuery('read');
        final restarted = TodoController(
          repository: repository,
          notificationService: MemoryNotificationService()..now = now,
          clock: () => now,
        );
        addTearDown(restarted.dispose);
        await restarted.loadTodos();
        expect(restarted.searchQuery, isEmpty);
        expect(restarted.visibleTodos, hasLength(7));
        expect(store.writes, writes);
      },
    );
  });

  test('loading prevents creation; failed load can be retried without changing category', () async {
    store.failRead = true;
    controller.selectCategory(TodoCategory.upcoming);
    expect(controller.isLoading, isTrue);
    await expectLater(
      controller.createTodo(title: 'Blocked'),
      throwsStateError,
    );
    await controller.loadTodos();
    expect(controller.loadError, isNotNull);
    expect(controller.canCreate, isFalse);
    store.failRead = false;
    await controller.loadTodos();
    expect(controller.loadError, isNull);
    expect(controller.isLoading, isFalse);
    expect(controller.canCreate, isTrue);
    expect(controller.category, TodoCategory.upcoming);
  });

  test('controller rejects blank titles and past due instants', () async {
    await controller.loadTodos();
    await expectLater(
      controller.createTodo(title: ' \n\t '),
      throwsA(isA<TodoValidationException>()),
    );
    await expectLater(
      controller.createTodo(
        title: 'Past',
        dueAt: now.subtract(const Duration(seconds: 1)),
      ),
      throwsA(isA<TodoValidationException>()),
    );
    expect(store.writes, 0);
    expect(controller.activeTodos, isEmpty);
  });

  test(
    'creation trims fields and persists before publishing visible state',
    () async {
      await controller.loadTodos();
      store.writeGate = Completer<void>();
      final pending = controller.createTodo(
        title: '  Read notes  ',
        description: '  Chapter 1  ',
        dueAt: DateTime(2026, 10, 8),
      );
      expect(controller.isSaving, isTrue);
      expect(controller.activeTodos, isEmpty);
      store.writeGate!.complete();
      final todo = await pending;
      expect(todo.title, 'Read notes');
      expect(todo.description, 'Chapter 1');
      expect(todo.createdAt, now);
      expect(controller.activeTodos.single.id, todo.id);
      expect(controller.isSaving, isFalse);
    },
  );

  test(
    'failed save leaves active state untouched and can be retried',
    () async {
      await controller.loadTodos();
      store.rejectWrite = true;
      await expectLater(
        controller.createTodo(title: 'Retry me'),
        throwsA(isA<TodoStorageException>()),
      );
      expect(controller.saveError, isNotNull);
      expect(controller.isSaving, isFalse);
      expect(controller.activeTodos, isEmpty);
      store.rejectWrite = false;
      final todo = await controller.createTodo(
        title: 'Retry me',
        description: '   ',
      );
      expect(todo.description, isNull);
      expect(controller.saveError, isNull);
      expect(controller.activeTodos.length, 1);
    },
  );

  test(
    'repeated submission while saving is rejected, not queued as a duplicate',
    () async {
      await controller.loadTodos();
      store.writeGate = Completer<void>();
      final pending = controller.createTodo(title: 'Once');
      await expectLater(controller.createTodo(title: 'Once'), throwsStateError);
      store.writeGate!.complete();
      await pending;
      expect(store.writes, 1);
      expect(controller.activeTodos.length, 1);
    },
  );

  test('local calendar filtering includes midnight, today overdue, and excludes completed', () async {
    var clock = now;
    final repository = SharedPreferencesTodoRepository(store: store);
    Todo item(String title, DateTime? due, int id, {bool completed = false}) =>
        Todo(
          id: title,
          title: title,
          dueAt: due?.toUtc(),
          createdAt: now.toUtc(),
          notificationId: id,
          isCompleted: completed,
        );
    await repository.saveTodos([
      item('Yesterday', DateTime(2026, 10, 6, 23, 59), 0),
      item('Midnight today', DateTime(2026, 10, 7), 1),
      item('Overdue today', DateTime(2026, 10, 7, 10), 2),
      item('Late today', DateTime(2026, 10, 7, 23, 59, 59), 3),
      item('Midnight tomorrow', DateTime(2026, 10, 8), 4),
      item('Later', DateTime(2026, 10, 9), 5),
      item('Undated', null, 6),
      item('Completed', DateTime(2026, 10, 7), 7, completed: true),
    ]);
    final local = TodoController(
      repository: repository,
      notificationService: MemoryNotificationService()..now = clock,
      clock: () => clock,
    );
    addTearDown(local.dispose);
    await local.loadTodos();
    expect(local.visibleTodos.length, 7);
    local.selectCategory(TodoCategory.today);
    expect(local.visibleTodos.map((todo) => todo.title), [
      'Midnight today',
      'Overdue today',
      'Late today',
    ]);
    local.selectCategory(TodoCategory.upcoming);
    expect(local.visibleTodos.map((todo) => todo.title), [
      'Midnight tomorrow',
      'Later',
    ]);
    clock = DateTime(2026, 10, 8, 0, 1);
    var notifications = 0;
    local.addListener(() => notifications++);
    local.refreshDateSensitiveResults();
    expect(notifications, 1);
    expect(local.visibleTodos.map((todo) => todo.title), ['Later']);
    local.selectCategory(TodoCategory.today);
    expect(local.visibleTodos.map((todo) => todo.title), ['Midnight tomorrow']);
    local.selectCategory(TodoCategory.all);
    expect(local.visibleTodos.length, 7);
  });

  test('reload during save waits and loads the latest mutation', () async {
    await controller.loadTodos();
    store.writeGate = Completer<void>();
    final pending = controller.createTodo(title: 'Saved');
    final reloading = controller.loadTodos();
    store.writeGate!.complete();
    await pending;
    await reloading;
    expect(controller.activeTodos.single.title, 'Saved');
  });

  test(
    'completion preserves category and query, and retry works after failure',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      await repository.saveTodos([
        Todo(
          id: 'a',
          title: 'Read notes',
          description: 'Project',
          dueAt: DateTime(2026, 10, 8).toUtc(),
          createdAt: now,
          notificationId: 0,
        ),
        Todo(
          id: 'b',
          title: 'Other notes',
          dueAt: DateTime(2026, 10, 7).toUtc(),
          createdAt: now,
          notificationId: 1,
        ),
      ]);
      await controller.loadTodos();
      controller.selectCategory(TodoCategory.upcoming);
      controller.setSearchQuery('read');
      store.rejectWrite = true;
      await expectLater(
        controller.completeTodo('a'),
        throwsA(isA<TodoStorageException>()),
      );
      expect(controller.visibleTodos.map((todo) => todo.id), ['a']);
      expect(controller.isCompleting('a'), isFalse);
      store.rejectWrite = false;
      final result = await controller.completeTodo('a');
      expect(result.isCompleted, isTrue);
      expect(controller.category, TodoCategory.upcoming);
      expect(controller.searchQuery, 'read');
      expect(controller.visibleTodos, isEmpty);
      expect(controller.activeTodos.map((todo) => todo.id), ['b']);
    },
  );

  test(
    'completed records disappear from All, Today, Upcoming, and search',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      await repository.saveTodos([
        Todo(
          id: 'today-item',
          title: 'Daily report',
          dueAt: now.add(const Duration(hours: 2)).toUtc(),
          createdAt: now,
          notificationId: 0,
        ),
        Todo(
          id: 'upcoming-item',
          title: 'Plan report',
          dueAt: now.add(const Duration(days: 1)).toUtc(),
          createdAt: now,
          notificationId: 1,
        ),
        Todo(
          id: 'undated-item',
          title: 'Report archive',
          createdAt: now,
          notificationId: 2,
        ),
      ]);
      await controller.loadTodos();
      controller.setSearchQuery('report');
      expect(controller.visibleTodos.length, 3);
      await controller.completeTodo('today-item');
      expect(controller.visibleTodos.map((todo) => todo.id), [
        'upcoming-item',
        'undated-item',
      ]);
      controller.selectCategory(TodoCategory.today);
      expect(controller.visibleTodos, isEmpty);
      controller.selectCategory(TodoCategory.upcoming);
      expect(controller.visibleTodos.map((todo) => todo.id), ['upcoming-item']);
      await controller.completeTodo('upcoming-item');
      expect(controller.visibleTodos, isEmpty);
      controller.selectCategory(TodoCategory.all);
      expect(controller.visibleTodos.map((todo) => todo.id), ['undated-item']);
      await controller.completeTodo('undated-item');
      expect(controller.visibleTodos, isEmpty);
      expect(controller.activeTodos, isEmpty);
    },
  );

  test('duplicate completion is blocked while pending and concurrent create is retained', () async {
    final repository = SharedPreferencesTodoRepository(store: store);
    final todo = await repository.createTodo(title: 'First', createdAt: now);
    await controller.loadTodos();
    store.writeGate = Completer<void>();
    final completion = controller.completeTodo(todo.id);
    expect(controller.isCompleting(todo.id), isTrue);
    await expectLater(controller.completeTodo(todo.id), throwsStateError);
    final creation = controller.createTodo(title: 'Concurrent');
    store.writeGate!.complete();
    await Future.wait([completion, creation]);
    expect(controller.activeTodos.map((item) => item.title), ['Concurrent']);
    final persisted = await repository.loadTodos();
    expect(persisted.length, 2);
    expect(persisted.first.isCompleted, isTrue);
  });

  test(
    'schedule failure keeps the saved TODO and retry reuses its ID',
    () async {
      await controller.loadTodos();
      notifications.failSchedule = true;
      final todo = await controller.createTodo(
        title: 'Save before reminder',
        dueAt: now.add(const Duration(hours: 1)),
      );
      expect(controller.activeTodos.single.id, todo.id);
      expect(controller.reminderScheduleError(todo.id), isNotNull);
      expect(store.writes, 1);
      notifications.failSchedule = false;
      await controller.retryScheduleReminder(todo.id);
      expect(controller.reminderScheduleError(todo.id), isNull);
      expect(notifications.scheduledTodos.map((item) => item.notificationId), [
        todo.notificationId,
        todo.notificationId,
      ]);
      expect(
        (await SharedPreferencesTodoRepository(
          store: store,
        ).loadTodos()).single.id,
        todo.id,
      );
      expect(store.writes, 1);
    },
  );

  test(
    'completion persists before cancellation and exposes cancellation retry',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Cancel when done',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      expect(notifications.pending.containsKey(todo.notificationId), isTrue);
      notifications.failCancel = true;
      await controller.completeTodo(todo.id);
      expect((await repository.loadTodos()).single.isCompleted, isTrue);
      expect(controller.activeTodos, isEmpty);
      expect(controller.reminderCancellationWarnings, hasLength(1));
      notifications.failCancel = false;
      await controller.retryCancellation(
        controller.reminderCancellationWarnings.single,
      );
      expect(notifications.pending.containsKey(todo.notificationId), isFalse);
      expect(controller.reminderCancellationWarnings, isEmpty);
    },
  );

  test(
    'an unchanged overdue due time allows title and description edits',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final overdue = await repository.createTodo(
        title: 'Overdue title',
        description: 'Old note',
        dueAt: now.subtract(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(days: 2)),
      );
      await controller.loadTodos();

      final edited = await controller.updateTodo(
        id: overdue.id,
        title: 'New title',
        description: 'New note',
        dueAt: overdue.dueAt,
      );

      expect(edited.title, 'New title');
      expect(edited.description, 'New note');
      expect(edited.dueAt, overdue.dueAt);
      await expectLater(
        controller.updateTodo(
          id: overdue.id,
          title: 'New title',
          dueAt: overdue.dueAt,
          dueTimeChanged: true,
        ),
        throwsA(isA<TodoValidationException>()),
      );
      expect((await repository.loadTodos()).single.title, 'New title');
    },
  );

  test(
    'edit changes category and search membership without resetting either',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Draft for tomorrow',
        description: 'Planning',
        dueAt: now.add(const Duration(days: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      controller.selectCategory(TodoCategory.upcoming);
      controller.setSearchQuery('draft');
      expect(controller.visibleTodos.single.id, todo.id);

      await controller.updateTodo(
        id: todo.id,
        title: 'Review today',
        description: 'Planning',
        dueAt: now.add(const Duration(hours: 1)),
        dueTimeChanged: true,
      );

      expect(controller.category, TodoCategory.upcoming);
      expect(controller.searchQuery, 'draft');
      expect(controller.visibleTodos, isEmpty);
      controller.selectCategory(TodoCategory.today);
      controller.setSearchQuery('review');
      expect(controller.visibleTodos.single.title, 'Review today');
    },
  );

  test(
    'editing title or due time reschedules with the same notification ID',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Before edit',
        description: 'Keep',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      final updatedDue = now.add(const Duration(hours: 2));

      final edited = await controller.updateTodo(
        id: todo.id,
        title: 'After edit',
        description: 'Keep',
        dueAt: updatedDue,
        dueTimeChanged: true,
      );

      expect(edited.notificationId, todo.notificationId);
      expect(notifications.cancelledIds, [todo.notificationId]);
      expect(notifications.scheduledTodos.map((item) => item.notificationId), [
        todo.notificationId,
        todo.notificationId,
      ]);
      expect(notifications.scheduledTodos.last.title, 'After edit');
      expect(notifications.scheduledTodos.last.dueAt, updatedDue);
      expect(notifications.pending[todo.notificationId]?.payload, todo.id);

      final cleared = await controller.updateTodo(
        id: todo.id,
        title: 'After edit',
        description: null,
        dueAt: null,
        dueTimeChanged: true,
      );
      expect(cleared.description, isNull);
      expect(cleared.dueAt, isNull);
      expect(notifications.pending, isEmpty);
      expect(notifications.cancelledIds, [
        todo.notificationId,
        todo.notificationId,
      ]);
      expect(notifications.scheduledTodos, hasLength(2));
    },
  );

  test(
    'reminder schedule failure keeps edit and retry uses latest saved record',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Original',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      notifications.failSchedule = true;

      final saved = await controller.updateTodo(
        id: todo.id,
        title: 'Persisted title',
        description: 'Latest description',
        dueAt: now.add(const Duration(hours: 2)),
        dueTimeChanged: true,
      );
      expect(saved.title, 'Persisted title');
      expect(controller.reminderScheduleError(todo.id), isNotNull);
      expect(
        (await repository.loadTodos()).single.description,
        'Latest description',
      );
      final writesAfterEdit = store.writes;

      notifications.failSchedule = false;
      await controller.retryScheduleReminder(todo.id);

      expect(store.writes, writesAfterEdit);
      expect(notifications.scheduledTodos.last.title, 'Persisted title');
      expect(
        notifications.scheduledTodos.last.dueAt,
        now.add(const Duration(hours: 2)),
      );
      expect(notifications.pending[todo.notificationId]?.payload, todo.id);
      expect(controller.reminderScheduleError(todo.id), isNull);
    },
  );

  test(
    'cancel failure after edit retries using latest fields and stable ID',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Before cancel failure',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      notifications.failCancel = true;

      await controller.updateTodo(
        id: todo.id,
        title: 'Saved despite cancel failure',
        dueAt: now.add(const Duration(hours: 2)),
        dueTimeChanged: true,
      );
      expect(controller.reminderCancellationWarnings, hasLength(1));
      expect(
        (await repository.loadTodos()).single.title,
        'Saved despite cancel failure',
      );

      notifications.failCancel = false;
      await controller.retryCancellation(
        controller.reminderCancellationWarnings.single,
      );

      expect(controller.reminderCancellationWarnings, isEmpty);
      expect(notifications.pending[todo.notificationId]?.payload, todo.id);
      expect(
        notifications.scheduledTodos.last.title,
        'Saved despite cancel failure',
      );
      expect(
        notifications.scheduledTodos.last.notificationId,
        todo.notificationId,
      );
    },
  );

  test(
    'serialized edit followed by completion preserves the latest fields',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Before',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      final editing = controller.updateTodo(
        id: todo.id,
        title: 'Edited first',
        dueAt: now.add(const Duration(hours: 2)),
        dueTimeChanged: true,
      );
      final completing = controller.completeTodo(todo.id);
      await Future.wait([editing, completing]);

      final persisted = (await repository.loadTodos()).single;
      expect(persisted.title, 'Edited first');
      expect(persisted.isCompleted, isTrue);
      expect(controller.activeTodos, isEmpty);
      expect(notifications.pending, isEmpty);
    },
  );

  test('startup reconciliation removes stale reminders and creates missing eligible ones', () async {
    final repository = SharedPreferencesTodoRepository(store: store);
    await repository.saveTodos([
      Todo(
        id: 'kept',
        title: 'Keep pending',
        dueAt: now.add(const Duration(hours: 2)),
        createdAt: now,
        notificationId: 10,
      ),
      Todo(
        id: 'schedule',
        title: 'Needs a reminder',
        dueAt: now.add(const Duration(hours: 3)),
        createdAt: now,
        notificationId: 14,
      ),
      Todo(
        id: 'done',
        title: 'Completed',
        dueAt: now.add(const Duration(days: 1)),
        isCompleted: true,
        createdAt: now,
        notificationId: 11,
      ),
      Todo(id: 'undated', title: 'Undated', createdAt: now, notificationId: 12),
      Todo(
        id: 'past',
        title: 'Too late',
        dueAt: now.add(const Duration(minutes: 5)),
        createdAt: now,
        notificationId: 13,
      ),
    ]);
    notifications.pending.addAll({
      10: const PendingReminder(id: 10, payload: 'kept'),
      11: const PendingReminder(id: 11, payload: 'done'),
      12: const PendingReminder(id: 12, payload: 'undated'),
      13: const PendingReminder(id: 13, payload: 'past'),
      99: const PendingReminder(id: 99, payload: 'missing'),
    });
    await controller.loadTodos();
    expect(notifications.cancelledIds.toSet(), {11, 12, 13, 99});
    expect(notifications.pending.keys.toSet(), {10, 14});
    expect(notifications.scheduledTodos.map((todo) => todo.id), ['schedule']);
  });

  test('load failure never reconciles as an empty store', () async {
    store.failRead = true;
    notifications.pending[9] = const PendingReminder(id: 9, payload: 'saved');
    await controller.loadTodos();
    expect(controller.loadError, isNotNull);
    expect(notifications.cancelledIds, isEmpty);
    expect(notifications.pending.containsKey(9), isTrue);
  });

  test(
    'retry reconciliation is inert until storage loads successfully',
    () async {
      store.failRead = true;
      notifications.pending[9] = const PendingReminder(id: 9, payload: 'saved');
      await controller.loadTodos();
      await controller.retryReminderReconciliation();

      expect(controller.loadError, isNotNull);
      expect(notifications.cancelledIds, isEmpty);
      expect(notifications.pending.containsKey(9), isTrue);
    },
  );

  test(
    'initialization failure does not become a storage load failure',
    () async {
      await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'Still visible', createdAt: now);
      notifications.failInitialize = true;

      await controller.loadTodos();

      expect(controller.loadError, isNull);
      expect(controller.reminderInitializationError, contains('init failed'));
      expect(controller.activeTodos.map((todo) => todo.title), [
        'Still visible',
      ]);
    },
  );

  test(
    'reconciliation clears cancellation warning when alarm is already gone',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Completed reminder',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      await controller.loadTodos();
      notifications.failCancel = true;
      await controller.completeTodo(todo.id);
      expect(controller.reminderCancellationWarnings, hasLength(1));

      notifications.failCancel = false;
      notifications.pending.remove(todo.notificationId);
      await controller.retryReminderReconciliation();

      expect(controller.reminderCancellationWarnings, isEmpty);
    },
  );

  test(
    'permission recheck after resume reconciles eligible reminders',
    () async {
      final repository = SharedPreferencesTodoRepository(store: store);
      final todo = await repository.createTodo(
        title: 'Permission returned',
        dueAt: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      notifications.permissionStatus =
          ReminderPermissionStatus.notificationsDenied;
      await controller.loadTodos();
      expect(notifications.pending, isEmpty);

      notifications.permissionStatus = ReminderPermissionStatus.enabled;
      await controller.onAppResumed();

      expect(
        controller.reminderPermissionStatus,
        ReminderPermissionStatus.enabled,
      );
      expect(notifications.pending[todo.notificationId]?.payload, todo.id);
    },
  );

  test(
    'late no-advance result is surfaced and any old alarm is canceled',
    () async {
      await controller.loadTodos();
      notifications.scheduleGate = Completer<void>();
      notifications.scheduleStarted = Completer<void>();
      final creating = controller.createTodo(
        title: 'Notice elapsed while scheduling',
        dueAt: now.add(const Duration(minutes: 11)),
      );
      await notifications.scheduleStarted!.future;
      final todo = controller.activeTodos.single;
      notifications.now = now.add(const Duration(minutes: 2));
      notifications.scheduleGate!.complete();

      await creating;

      expect(controller.reminderHasNoAdvanceNotice(todo.id), isTrue);
      expect(controller.reminderScheduleError(todo.id), isNull);
      expect(notifications.pending, isEmpty);
      expect(notifications.cancelledIds, [todo.notificationId]);
    },
  );

  test('serialized create scheduling followed by completion cannot leave a pending reminder', () async {
    await controller.loadTodos();
    notifications.scheduleGate = Completer<void>();
    notifications.scheduleStarted = Completer<void>();
    final creating = controller.createTodo(
      title: 'Race reminder',
      dueAt: now.add(const Duration(hours: 1)),
    );
    await notifications.scheduleStarted!.future;
    final todo = controller.activeTodos.single;
    final completing = controller.completeTodo(todo.id);
    notifications.scheduleGate!.complete();
    await Future.wait([creating, completing]);
    expect(
      (await SharedPreferencesTodoRepository(
        store: store,
      ).loadTodos()).single.isCompleted,
      isTrue,
    );
    expect(notifications.pending, isEmpty);
    expect(notifications.cancelledIds, [todo.notificationId]);
  });
}

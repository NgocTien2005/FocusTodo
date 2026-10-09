import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';

import 'support/memory_document_store.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);
  late MemoryDocumentStore store;
  late TodoController controller;
  setUp(() {
    store = MemoryDocumentStore();
    controller = TodoController(
      repository: SharedPreferencesTodoRepository(store: store),
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
    final local = TodoController(repository: repository, clock: () => clock);
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
}

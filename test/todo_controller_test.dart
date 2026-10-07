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

  test(
    'reload during save is rejected without blocking a later reload',
    () async {
      await controller.loadTodos();
      store.writeGate = Completer<void>();
      final pending = controller.createTodo(title: 'Saved');
      await expectLater(controller.loadTodos(), throwsStateError);
      store.writeGate!.complete();
      await pending;
      await controller.loadTodos();
      expect(controller.activeTodos.single.title, 'Saved');
    },
  );
}

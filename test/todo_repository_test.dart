import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/controllers/todo_controller.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/repositories/shared_preferences_todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 7, 12);
  const key = SharedPreferencesTodoDocumentStore.storageKey;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first launch loads empty without writing', () async {
    final repository = SharedPreferencesTodoRepository();
    expect(await repository.loadTodos(), isEmpty);
    expect((await SharedPreferences.getInstance()).getString(key), isNull);
  });

  test(
    'dated and undated TODOs round trip through fresh repository/controller',
    () async {
      final first = SharedPreferencesTodoRepository();
      final due = DateTime(2026, 10, 8, 9, 30);
      final dated = await first.createTodo(
        title: 'Dated',
        description: 'Notes',
        dueAt: due,
        createdAt: now,
      );
      final undated = await first.createTodo(title: 'Undated', createdAt: now);
      final fresh = SharedPreferencesTodoRepository();
      final controller = TodoController(repository: fresh, clock: () => now);
      addTearDown(controller.dispose);
      await controller.loadTodos();
      expect(controller.loadError, isNull);
      expect(controller.activeTodos.map((todo) => todo.toJson()).toList(), [
        dated.toJson(),
        undated.toJson(),
      ]);
      expect(controller.activeTodos.first.dueAt!.isAtSameMomentAs(due), isTrue);
      expect(controller.activeTodos.last.dueAt, isNull);
      final document = jsonDecode(
        (await SharedPreferences.getInstance()).getString(key)!,
      ) as Map<String, dynamic>;
      expect(document['schemaVersion'], 1);
      expect(document['nextTodoId'], 3);
      expect(document['nextNotificationId'], 2);
      expect(
        (document['todos'] as List).first['dueAt'],
        due.toUtc().toIso8601String(),
      );
    },
  );

  for (final raw in [
    'not JSON',
    '{"schemaVersion":99}',
    '{"schemaVersion":1,"todos":[]}',
  ]) {
    test(
      'unreadable/unsupported data is surfaced and never overwritten: $raw',
      () async {
        SharedPreferences.setMockInitialValues({key: raw});
        final repository = SharedPreferencesTodoRepository();
        await expectLater(
          repository.loadTodos(),
          throwsA(isA<TodoStorageException>()),
        );
        await expectLater(
          repository.createTodo(title: 'New', createdAt: now),
          throwsA(isA<TodoStorageException>()),
        );
        await expectLater(
          repository.saveTodos([]),
          throwsA(isA<TodoStorageException>()),
        );
        expect((await SharedPreferences.getInstance()).getString(key), raw);
      },
    );
  }

  test(
    'notification and TODO allocators survive restart even with an empty list',
    () async {
      final store = MemoryDocumentStore();
      final first = await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'First', createdAt: now);
      final document = jsonDecode(store.document!) as Map<String, dynamic>;
      // Simulates future removal while retaining high-water marks, not a delete API.
      document['todos'] = [];
      store.document = jsonEncode(document);
      final second = await SharedPreferencesTodoRepository(store: store)
          .createTodo(title: 'Second', createdAt: now);
      expect(second.id, isNot(first.id));
      expect(second.notificationId, greaterThan(first.notificationId));
      expect(second.notificationId, inInclusiveRange(0, 2147483647));
    },
  );

  test(
    'concurrent creates from different instances do not lose TODOs or IDs',
    () async {
      final store = MemoryDocumentStore();
      final first = SharedPreferencesTodoRepository(store: store);
      final second = SharedPreferencesTodoRepository(store: store);
      final todos = await Future.wait([
        first.createTodo(title: 'First', createdAt: now),
        second.createTodo(title: 'Second', createdAt: now),
      ]);
      expect((await first.loadTodos()).length, 2);
      expect(todos.map((todo) => todo.id).toSet().length, 2);
      expect(todos.map((todo) => todo.notificationId).toSet().length, 2);
    },
  );

  test(
    'concurrent snapshot saves preserve additions from both snapshots',
    () async {
      final store = MemoryDocumentStore();
      final first = SharedPreferencesTodoRepository(store: store);
      final second = SharedPreferencesTodoRepository(store: store);
      Todo item(String id, int notificationId) => Todo(
        id: id,
        title: id,
        createdAt: now,
        notificationId: notificationId,
      );
      await Future.wait([
        first.saveTodos([item('import-a', 10)]),
        second.saveTodos([item('import-b', 11)]),
      ]);
      expect((await first.loadTodos()).map((todo) => todo.id), [
        'import-a',
        'import-b',
      ]);
      final added = await first.createTodo(title: 'Created', createdAt: now);
      expect(added.notificationId, 12);
    },
  );

  test(
    'false write result and thrown failures do not succeed or poison retry',
    () async {
      final store = MemoryDocumentStore();
      final repository = SharedPreferencesTodoRepository(store: store);
      await repository.createTodo(title: 'Existing', createdAt: now);
      final original = store.document;
      store.rejectWrite = true;
      await expectLater(
        repository.createTodo(title: 'Rejected', createdAt: now),
        throwsA(isA<TodoStorageException>()),
      );
      expect(store.document, original);
      store.rejectWrite = false;
      store.throwOnWrite = true;
      await expectLater(
        repository.createTodo(title: 'Failed', createdAt: now),
        throwsA(isA<TodoStorageException>()),
      );
      expect(store.document, original);
      store.throwOnWrite = false;
      expect(
        (await repository.createTodo(
          title: 'Retry',
          createdAt: now,
        )).notificationId,
        1,
      );
    },
  );

  test('storage read failure is surfaced', () async {
    final store = MemoryDocumentStore()..failRead = true;
    final repository = SharedPreferencesTodoRepository(store: store);
    await expectLater(
      repository.loadTodos(),
      throwsA(isA<TodoStorageException>()),
    );
    await expectLater(
      repository.createTodo(title: 'Blocked', createdAt: now),
      throwsA(isA<TodoStorageException>()),
    );
    expect(store.writes, 0);
  });

  test(
    'invalid allocator state is preserved instead of reusing an ID',
    () async {
      final store = MemoryDocumentStore();
      final repository = SharedPreferencesTodoRepository(store: store);
      await repository.createTodo(title: 'First', createdAt: now);
      final document = jsonDecode(store.document!) as Map<String, dynamic>;
      document['nextNotificationId'] = 0;
      store.document = jsonEncode(document);
      final corrupted = store.document;
      await expectLater(
        repository.loadTodos(),
        throwsA(isA<TodoStorageException>()),
      );
      await expectLater(
        repository.createTodo(title: 'Blocked', createdAt: now),
        throwsA(isA<TodoStorageException>()),
      );
      expect(store.document, corrupted);
    },
  );

  test('last int32 notification ID is valid; exhaustion is surfaced', () async {
    final store = MemoryDocumentStore()
      ..document = jsonEncode({
        'schemaVersion': 1,
        'todos': [],
        'nextTodoId': 1,
        'nextNotificationId': 2147483647,
      });
    final repository = SharedPreferencesTodoRepository(store: store);
    expect(
      (await repository.createTodo(
        title: 'Last ID',
        createdAt: now,
      )).notificationId,
      2147483647,
    );
    await expectLater(
      repository.createTodo(title: 'Exhausted', createdAt: now),
      throwsA(isA<TodoStorageException>()),
    );
    expect((await repository.loadTodos()).length, 1);
  });

  test('snapshot saves cannot reuse historical IDs after a restart', () async {
    final store = MemoryDocumentStore();
    await SharedPreferencesTodoRepository(store: store)
        .createTodo(title: 'First', createdAt: now);
    final document = jsonDecode(store.document!) as Map<String, dynamic>;
    document['todos'] = [];
    store.document = jsonEncode(document);
    final original = store.document;
    final fresh = SharedPreferencesTodoRepository(store: store);
    await expectLater(
      fresh.saveTodos([
        Todo(
          id: 'new-import',
          title: 'Reused reminder ID',
          createdAt: now,
          notificationId: 0,
        ),
      ]),
      throwsA(isA<TodoStorageException>()),
    );
    await expectLater(
      fresh.saveTodos([
        Todo(
          id: 'todo-1',
          title: 'Reused TODO ID',
          createdAt: now,
          notificationId: 1,
        ),
      ]),
      throwsA(isA<TodoStorageException>()),
    );
    expect(store.document, original);
  });
}

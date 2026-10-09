import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';
import 'todo_repository.dart';

class TodoStorageException implements Exception {
  const TodoStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Storage seam for testing platform failures and rejected writes.
abstract interface class TodoDocumentStore {
  Future<String?> read();
  Future<bool> write(String document);
}

class SharedPreferencesTodoDocumentStore implements TodoDocumentStore {
  static const storageKey = 'focus_todo.document';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    // Refresh the legacy cache, including after a rejected platform write.
    await preferences.reload();
    return preferences.getString(storageKey);
  }

  @override
  Future<bool> write(String document) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(storageKey, document);
  }
}

/// A shared queue serializes reads/mutations across instances in this isolate.
/// Background-isolate writers are outside this small assignment's scope.
class SharedPreferencesTodoRepository implements TodoRepository {
  SharedPreferencesTodoRepository({TodoDocumentStore? store})
    : _store = store ?? SharedPreferencesTodoDocumentStore();

  static const schemaVersion = 1;
  static const _maxNotificationId = 2147483647;
  static const _maxTodoId = 9007199254740991;
  static Future<void>? _tail;
  final TodoDocumentStore _store;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail?.then((_) => operation()) ?? operation();
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) {
        _tail = null;
      }
    });
    return result;
  }

  @override
  Future<List<Todo>> loadTodos() => _serialized(() async {
    final document = await _read();
    return List<Todo>.unmodifiable(document.todos);
  });

  @override
  Future<Todo> createTodo({
    required String title,
    String? description,
    DateTime? dueAt,
    required DateTime createdAt,
  }) => _serialized(() async {
    final document = await _read();
    if (document.nextNotificationId > _maxNotificationId ||
        document.nextTodoId >= _maxTodoId) {
      throw const TodoStorageException('No more TODO IDs are available.');
    }
    final todo = Todo(
      id: 'todo-${document.nextTodoId}',
      title: title,
      description: description,
      dueAt: dueAt,
      createdAt: createdAt,
      notificationId: document.nextNotificationId,
    );
    final updated = _Document(
      todos: [...document.todos, todo],
      nextTodoId: document.nextTodoId + 1,
      nextNotificationId: document.nextNotificationId + 1,
    );
    _validate(updated);
    await _write(updated);
    return todo;
  });

  @override
  Future<Todo> completeTodo(String id) => _serialized(() async {
    final document = await _read();
    final index = document.todos.indexWhere((todo) => todo.id == id);
    if (index < 0) throw TodoNotFoundException(id);
    final current = document.todos[index];
    if (current.isCompleted) return current;
    final completed = current.copyWith(isCompleted: true);
    final todos = List<Todo>.of(document.todos)..[index] = completed;
    final updated = _Document(
      todos: todos,
      nextTodoId: document.nextTodoId,
      nextNotificationId: document.nextNotificationId,
    );
    _validate(updated);
    await _write(updated);
    return completed;
  });

  @override
  Future<void> saveTodos(List<Todo> todos) {
    final snapshot = List<Todo>.of(todos);
    return _serialized(() async {
      final document = await _read();
      final merged = {for (final todo in document.todos) todo.id: todo};
      final submittedIds = <String>{};
      for (final todo in snapshot) {
        if (!submittedIds.add(todo.id)) {
          throw const TodoStorageException(
            'Duplicate TODO IDs cannot be saved.',
          );
        }
        final existing = merged[todo.id];
        final sequence = _todoSequence(todo.id);
        if (existing == null &&
            (todo.notificationId < document.nextNotificationId ||
                (sequence != null && sequence < document.nextTodoId))) {
          throw const TodoStorageException(
            'Previously allocated IDs cannot be reused.',
          );
        }
        if (existing != null &&
            existing.notificationId != todo.notificationId) {
          throw const TodoStorageException(
            'A TODO notification ID must stay stable.',
          );
        }
        merged[todo.id] = todo;
      }
      var nextTodoId = document.nextTodoId;
      var nextNotificationId = document.nextNotificationId;
      for (final todo in merged.values) {
        final allocated = _todoSequence(todo.id);
        if (allocated != null && allocated >= nextTodoId) {
          nextTodoId = allocated + 1;
        }
        if (todo.notificationId >= nextNotificationId) {
          nextNotificationId = todo.notificationId + 1;
        }
      }
      final updated = _Document(
        todos: merged.values.toList(),
        nextTodoId: nextTodoId,
        nextNotificationId: nextNotificationId,
      );
      _validate(updated);
      await _write(updated);
    });
  }

  Future<_Document> _read() async {
    String? raw;
    try {
      raw = await _store.read();
    } catch (_) {
      throw const TodoStorageException(
        'Could not read saved TODOs. Please retry.',
      );
    }
    if (raw == null) {
      return const _Document(todos: [], nextTodoId: 1, nextNotificationId: 0);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['schemaVersion'];
      if (version is! int) {
        throw const FormatException('Missing schema version');
      }
      if (version != schemaVersion) {
        throw TodoStorageException(
          'Unsupported TODO schema version: $version. Saved data was preserved.',
        );
      }
      final document = _Document(
        todos: (json['todos'] as List<dynamic>)
            .map((item) => Todo.fromJson(item as Map<String, dynamic>))
            .toList(),
        nextTodoId: json['nextTodoId'] as int,
        nextNotificationId: json['nextNotificationId'] as int,
      );
      _validate(document);
      return document;
    } on TodoStorageException {
      rethrow;
    } catch (_) {
      throw const TodoStorageException(
        'Saved TODO data is unreadable. It was preserved; restore a valid backup before retrying.',
      );
    }
  }

  static int? _todoSequence(String id) {
    final match = RegExp(r'^todo-([0-9]+)$').firstMatch(id);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static void _validate(_Document document) {
    if (document.nextTodoId < 1 ||
        document.nextTodoId > _maxTodoId ||
        document.nextNotificationId < 0 ||
        document.nextNotificationId > _maxNotificationId + 1) {
      throw const FormatException('Invalid ID allocators');
    }
    final ids = <String>{};
    final notificationIds = <int>{};
    for (final todo in document.todos) {
      final sequence = _todoSequence(todo.id);
      if (todo.id.trim().isEmpty ||
          todo.title.trim().isEmpty ||
          !ids.add(todo.id) ||
          !notificationIds.add(todo.notificationId) ||
          todo.notificationId < 0 ||
          todo.notificationId > _maxNotificationId ||
          todo.notificationId >= document.nextNotificationId ||
          (sequence != null && sequence >= document.nextTodoId)) {
        throw const FormatException('Invalid TODOs or allocator collisions');
      }
    }
  }

  Future<void> _write(_Document document) async {
    try {
      final saved = await _store.write(
        jsonEncode({
          'schemaVersion': schemaVersion,
          'nextTodoId': document.nextTodoId,
          'nextNotificationId': document.nextNotificationId,
          'todos': document.todos.map((todo) => todo.toJson()).toList(),
        }),
      );
      if (!saved) {
        throw const TodoStorageException(
          'Could not save this TODO. Please retry.',
        );
      }
    } on TodoStorageException {
      rethrow;
    } catch (_) {
      throw const TodoStorageException(
        'Could not save this TODO. Please retry.',
      );
    }
  }
}

class _Document {
  const _Document({
    required this.todos,
    required this.nextTodoId,
    required this.nextNotificationId,
  });
  final List<Todo> todos;
  final int nextTodoId;
  final int nextNotificationId;
}

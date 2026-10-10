import '../models/todo.dart';

/// Implementations propagate storage/decoding errors instead of hiding them.
abstract interface class TodoRepository {
  Future<List<Todo>> loadTodos();

  /// Upserts these TODOs, preserving other stored items and stable IDs.
  /// Deletion will require an explicit operation in a future feature.
  Future<void> saveTodos(List<Todo> todos);

  /// Saves the item and monotonic ID allocators in the same document.
  Future<Todo> createTodo({
    required String title,
    String? description,
    DateTime? dueAt,
    required DateTime createdAt,
  });

  /// Marks the latest stored record complete without replacing other data.
  /// Throws [TodoNotFoundException] when [id] has not been stored.
  Future<Todo> completeTodo(String id);

  /// Updates editable fields on the latest stored record without changing IDs,
  /// creation time, completion state, unrelated records, or allocators.
  Future<Todo> updateTodo({
    required String id,
    required String title,
    String? description,
    DateTime? dueAt,
  });
}

class TodoNotFoundException implements Exception {
  const TodoNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'TODO "$id" was not found.';
}

class TodoAlreadyCompletedException implements Exception {
  const TodoAlreadyCompletedException(this.id);
  final String id;
  @override
  String toString() => 'Completed TODO "$id" cannot be edited.';
}

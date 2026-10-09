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
}

class TodoNotFoundException implements Exception {
  const TodoNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'TODO "$id" was not found.';
}

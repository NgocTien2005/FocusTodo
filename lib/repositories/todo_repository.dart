import '../models/todo.dart';

/// Persistence contract. SharedPreferences JSON implementation is coming next.
/// Implementations must propagate storage/decoding errors, not hide them.
abstract interface class TodoRepository {
  Future<List<Todo>> loadTodos();
  Future<void> saveTodos(List<Todo> todos);
}

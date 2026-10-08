import 'package:flutter/foundation.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';

enum TodoCategory { all, today, upcoming }

typedef TodoClock = DateTime Function();

class TodoValidationException implements Exception {
  const TodoValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TodoController extends ChangeNotifier {
  TodoController({required this.repository, TodoClock? clock})
    : _clock = clock ?? DateTime.now;

  final TodoRepository repository;
  final TodoClock _clock;
  List<Todo> _todos = [];
  TodoCategory _category = TodoCategory.all;
  String _searchQuery = '';
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _disposed = false;
  String? _loadError;
  String? _saveError;
  Future<void>? _loadFuture;

  TodoCategory get category => _category;
  String get searchQuery => _searchQuery;
  bool get hasSearchQuery => _searchQuery.trim().isNotEmpty;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;
  bool get canCreate => _loaded && !_loading && !_saving && _loadError == null;
  DateTime get currentTime => _clock();
  List<Todo> get activeTodos =>
      List.unmodifiable(_todos.where((todo) => !todo.isCompleted));

  List<Todo> get visibleTodos {
    final today = _calendarDate(currentTime.toLocal());
    final query = _searchQuery.trim().toLowerCase();
    return List.unmodifiable(
      activeTodos.where((todo) {
        if (query.isNotEmpty &&
            !todo.title.toLowerCase().contains(query) &&
            !(todo.description?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
        if (_category == TodoCategory.all) return true;
        final due = todo.dueAt?.toLocal();
        if (due == null) return false;
        final day = _calendarDate(due);
        return _category == TodoCategory.today ? day == today : day > today;
      }),
    );
  }

  static int _calendarDate(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;
  static String? validateTitle(String title) =>
      title.trim().isEmpty ? 'Enter a title.' : null;
  static String? validateDueAt(DateTime? dueAt, DateTime now) =>
      dueAt != null && dueAt.isBefore(now)
      ? 'Choose a due date and time in the future.'
      : null;

  Future<void> loadTodos() {
    if (_saving) {
      return Future.error(
        StateError('Wait for the current save before loading TODOs.'),
      );
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    _loading = true;
    _loadError = null;
    _notify();
    try {
      final todos = await repository.loadTodos();
      if (!_disposed) {
        _todos = List.of(todos);
        _loaded = true;
      }
    } catch (error) {
      if (!_disposed) _loadError = error.toString();
    } finally {
      _loading = false;
      _loadFuture = null;
      _notify();
    }
  }

  Future<Todo> createTodo({
    required String title,
    String? description,
    DateTime? dueAt,
  }) async {
    if (_saving) throw StateError('A TODO is already being saved.');
    if (!canCreate) {
      throw StateError('Load TODOs successfully before creating one.');
    }
    final now = currentTime;
    final validation = validateTitle(title) ?? validateDueAt(dueAt, now);
    if (validation != null) throw TodoValidationException(validation);
    final trimmedDescription = description?.trim();
    _saving = true;
    _saveError = null;
    _notify();
    try {
      final todo = await repository.createTodo(
        title: title.trim(),
        description: trimmedDescription == null || trimmedDescription.isEmpty
            ? null
            : trimmedDescription,
        dueAt: dueAt,
        createdAt: now,
      );
      if (!_disposed) _todos = [..._todos, todo];
      return todo;
    } catch (error) {
      if (!_disposed) _saveError = error.toString();
      rethrow;
    } finally {
      _saving = false;
      _notify();
    }
  }

  void selectCategory(TodoCategory category) {
    if (_category == category) return;
    _category = category;
    _notify();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _notify();
  }

  void refreshDateSensitiveResults() => _notify();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

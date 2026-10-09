import 'package:flutter/foundation.dart';

import '../models/todo.dart';
import '../repositories/todo_repository.dart';
import '../services/notification_service.dart';

enum TodoCategory { all, today, upcoming }

typedef TodoClock = DateTime Function();

class TodoValidationException implements Exception {
  const TodoValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ReminderCancellationWarning {
  const ReminderCancellationWarning({
    required this.notificationId,
    required this.todoId,
    required this.title,
    required this.error,
  });

  final int notificationId;
  final String? todoId;
  final String title;
  final String error;
}

class TodoController extends ChangeNotifier {
  TodoController({
    required this.repository,
    required this.notificationService,
    TodoClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final TodoRepository repository;
  final NotificationService notificationService;
  final TodoClock _clock;
  List<Todo> _todos = [];
  TodoCategory _category = TodoCategory.all;
  String _searchQuery = '';
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _disposed = false;
  final Set<String> _completingIds = {};
  final Map<String, String> _reminderScheduleErrors = {};
  final Map<String, ReminderCancellationWarning> _reminderCancellationWarnings =
      {};
  final Set<String> _noAdvanceReminderIds = {};
  String? _loadError;
  String? _saveError;
  String? _reminderInitializationError;
  String? _reminderReconciliationError;
  ReminderPermissionStatus? _reminderPermissionStatus;
  bool _requestingReminderPermissions = false;
  bool _reconcilingReminders = false;
  Future<void>? _loadFuture;
  Future<void> _operationTail = Future<void>.value();

  TodoCategory get category => _category;
  String get searchQuery => _searchQuery;
  bool get hasSearchQuery => _searchQuery.trim().isNotEmpty;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;
  String? get reminderInitializationError => _reminderInitializationError;
  String? get reminderReconciliationError => _reminderReconciliationError;
  ReminderPermissionStatus? get reminderPermissionStatus =>
      _reminderPermissionStatus;
  bool get isRequestingReminderPermissions => _requestingReminderPermissions;
  bool get isReconcilingReminders => _reconcilingReminders;
  List<ReminderCancellationWarning> get reminderCancellationWarnings =>
      List.unmodifiable(_reminderCancellationWarnings.values);
  Map<String, String> get reminderScheduleErrors =>
      Map.unmodifiable(_reminderScheduleErrors);
  bool reminderHasNoAdvanceNotice(String todoId) =>
      _noAdvanceReminderIds.contains(todoId);
  String? reminderScheduleError(String todoId) =>
      _reminderScheduleErrors[todoId];
  bool get canRetryReminderSetup =>
      _loaded && !_loading && !_requestingReminderPermissions;
  bool get canCreate => _loaded && !_loading && !_saving && _loadError == null;
  bool isCompleting(String id) => _completingIds.contains(id);
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
    return _loadFuture ??= _load();
  }

  Future<void> _load() {
    _loading = true;
    _loadError = null;
    _notify();
    return _enqueue(() async {
      try {
        final todos = await repository.loadTodos();
        if (!_disposed) {
          _todos = List.of(todos);
          _loaded = true;
          _loading = false;
          _notify();
        }
        await _reconcileRemindersLocked(todos);
      } catch (error) {
        if (!_disposed) _loadError = error.toString();
      } finally {
        _loading = false;
        _loadFuture = null;
        _notify();
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  DateTime _reminderInstant(Todo todo) => reminderInstantFor(todo);

  bool _hasAdvanceNotice(Todo todo) =>
      todo.dueAt != null && _reminderInstant(todo).isAfter(currentTime.toUtc());

  Future<ReminderPermissionStatus?> _initializeAndCheckPermission() async {
    try {
      await notificationService.initialize();
      _reminderInitializationError = null;
      _reminderPermissionStatus = await notificationService
          .checkPermissionStatus();
      _notify();
      return _reminderPermissionStatus;
    } catch (error) {
      _reminderInitializationError = error.toString();
      _notify();
      return null;
    }
  }

  Future<void> _scheduleTodoReminderLocked(
    Todo todo, {
    ReminderPermissionStatus? permissionStatus,
  }) async {
    if (todo.isCompleted || todo.dueAt == null) return;
    if (!_hasAdvanceNotice(todo)) {
      _noAdvanceReminderIds.add(todo.id);
      _reminderScheduleErrors.remove(todo.id);
      await _cancelReminderLocked(
        notificationId: todo.notificationId,
        todoId: todo.id,
        title: todo.title,
      );
      _notify();
      return;
    }
    try {
      final status = permissionStatus ?? await _initializeAndCheckPermission();
      if (status != ReminderPermissionStatus.enabled) {
        _reminderScheduleErrors[todo.id] =
            status == null || status == ReminderPermissionStatus.unavailable
            ? 'Reminder service is unavailable.'
            : status == ReminderPermissionStatus.notificationsDenied
            ? 'Notification permission is disabled.'
            : 'Exact alarm access is disabled.';
        _notify();
        return;
      }
      final result = await notificationService.scheduleReminder(todo);
      if (result == ReminderScheduleResult.noAdvanceNotice) {
        _noAdvanceReminderIds.add(todo.id);
        await _cancelReminderLocked(
          notificationId: todo.notificationId,
          todoId: todo.id,
          title: todo.title,
        );
      } else {
        _noAdvanceReminderIds.remove(todo.id);
      }
      _reminderScheduleErrors.remove(todo.id);
    } catch (error) {
      _reminderScheduleErrors[todo.id] = error.toString();
    }
    _notify();
  }

  void _recordCancellationFailure({
    required int notificationId,
    required String? todoId,
    required String title,
    required Object error,
  }) {
    _reminderCancellationWarnings['$notificationId'] =
        ReminderCancellationWarning(
          notificationId: notificationId,
          todoId: todoId,
          title: title,
          error: error.toString(),
        );
    _notify();
  }

  Future<void> _cancelReminderLocked({
    required int notificationId,
    required String? todoId,
    required String title,
  }) async {
    try {
      await notificationService.cancelReminder(notificationId);
      _reminderCancellationWarnings.remove('$notificationId');
      _notify();
    } catch (error) {
      _recordCancellationFailure(
        notificationId: notificationId,
        todoId: todoId,
        title: title,
        error: error,
      );
    }
  }

  Future<void> _reconcileRemindersLocked(List<Todo> todos) async {
    // Reconciliation may cancel platform alarms, so only use an authoritative
    // snapshot obtained from a successful storage load.
    if (!_loaded || _loading || _loadError != null) return;
    _reconcilingReminders = true;
    _reminderReconciliationError = null;
    _notify();
    try {
      final permission = await _initializeAndCheckPermission();
      if (permission == null) return;
      final pending = await notificationService.pendingReminders();
      final pendingIds = pending.map((reminder) => '${reminder.id}').toSet();
      _reminderCancellationWarnings.removeWhere(
        (notificationId, _) => !pendingIds.contains(notificationId),
      );
      final byNotificationId = {
        for (final todo in todos) todo.notificationId: todo,
      };
      final pendingById = {for (final item in pending) item.id: item};
      final failedCancellationIds = <int>{};
      for (final reminder in pending) {
        final todo = byNotificationId[reminder.id];
        final eligible =
            todo != null &&
            !todo.isCompleted &&
            todo.dueAt != null &&
            _hasAdvanceNotice(todo) &&
            reminder.payload == todo.id;
        if (!eligible) {
          final oldWarning = _reminderCancellationWarnings['${reminder.id}'];
          await _cancelReminderLocked(
            notificationId: reminder.id,
            todoId: todo?.id ?? oldWarning?.todoId ?? reminder.payload,
            title: todo?.title ?? oldWarning?.title ?? 'TODO reminder',
          );
          if (_reminderCancellationWarnings.containsKey('${reminder.id}')) {
            failedCancellationIds.add(reminder.id);
          }
        }
      }
      if (permission != ReminderPermissionStatus.enabled) return;
      for (final todo in todos) {
        if (todo.isCompleted ||
            todo.dueAt == null ||
            !_hasAdvanceNotice(todo)) {
          continue;
        }
        final pendingReminder = pendingById[todo.notificationId];
        if (pendingReminder?.payload == todo.id) {
          _reminderScheduleErrors.remove(todo.id);
          continue;
        }
        if (failedCancellationIds.contains(todo.notificationId)) continue;
        await _scheduleTodoReminderLocked(todo, permissionStatus: permission);
      }
    } catch (error) {
      _reminderReconciliationError = error.toString();
    } finally {
      _reconcilingReminders = false;
      _notify();
    }
  }

  Future<bool> requestReminderPermissions() async {
    if (_requestingReminderPermissions) return false;
    _requestingReminderPermissions = true;
    _notify();
    try {
      return await _enqueue(() async {
        try {
          await notificationService.initialize();
          _reminderInitializationError = null;
          _reminderPermissionStatus = await notificationService
              .requestPermissions();
          if (_reminderPermissionStatus == ReminderPermissionStatus.enabled) {
            await _reconcileRemindersLocked(_todos);
          }
          return _reminderPermissionStatus == ReminderPermissionStatus.enabled;
        } catch (error) {
          _reminderInitializationError = error.toString();
          return false;
        } finally {
          _requestingReminderPermissions = false;
          _notify();
        }
      });
    } catch (_) {
      _requestingReminderPermissions = false;
      _notify();
      rethrow;
    }
  }

  Future<void> retryReminderReconciliation() => _enqueue(() async {
    if (!_loaded || _loading || _loadError != null) return;
    await _reconcileRemindersLocked(_todos);
  });

  Future<void> onAppResumed() => _enqueue(() async {
    if (!_loaded || _loading || _loadError != null) return;
    await _reconcileRemindersLocked(_todos);
  });

  Future<void> retryScheduleReminder(String todoId) => _enqueue(() async {
    final matching = _todos.where((item) => item.id == todoId);
    final todo = matching.isEmpty ? null : matching.first;
    if (todo == null || todo.isCompleted || todo.dueAt == null) return;
    await _scheduleTodoReminderLocked(todo);
  });

  Future<void> retryCancellation(ReminderCancellationWarning warning) =>
      _enqueue(
        () => _cancelReminderLocked(
          notificationId: warning.notificationId,
          todoId: warning.todoId,
          title: warning.title,
        ),
      );

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
      final todo = await _enqueue(() async {
        final saved = await repository.createTodo(
          title: title.trim(),
          description: trimmedDescription == null || trimmedDescription.isEmpty
              ? null
              : trimmedDescription,
          dueAt: dueAt,
          createdAt: now,
        );
        if (!_disposed) _todos = [..._todos, saved];
        if (saved.dueAt != null) await _scheduleTodoReminderLocked(saved);
        return saved;
      });
      return todo;
    } catch (error) {
      if (!_disposed) _saveError = error.toString();
      rethrow;
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<Todo> completeTodo(String id) async {
    if (!_loaded || _loading || _loadError != null) {
      throw StateError('Load TODOs successfully before completing one.');
    }
    if (_completingIds.contains(id)) {
      throw StateError('This TODO is already being completed.');
    }
    if (!_todos.any((todo) => todo.id == id && !todo.isCompleted)) {
      throw TodoNotFoundException(id);
    }
    _completingIds.add(id);
    _notify();
    try {
      return await _enqueue(() async {
        final todo = await repository.completeTodo(id);
        if (!_disposed) {
          _todos = [for (final item in _todos) item.id == id ? todo : item];
        }
        await _cancelReminderLocked(
          notificationId: todo.notificationId,
          todoId: todo.id,
          title: todo.title,
        );
        return todo;
      });
    } finally {
      _completingIds.remove(id);
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

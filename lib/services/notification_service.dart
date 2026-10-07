import '../models/todo.dart';

/// Contract only: plugin integration and runtime permissions are coming next.
/// Initialization must obtain the device timezone before scheduling.
abstract interface class NotificationService {
  Future<void> initialize();
  Future<bool> requestPermissions();

  /// Schedule dueAt minus ten minutes; reject past reminders and undated TODOs.
  /// Reuse the persisted notificationId. Surface permission/scheduling failures.
  Future<void> scheduleReminder(Todo todo);
  Future<void> cancelReminder(int notificationId);
}

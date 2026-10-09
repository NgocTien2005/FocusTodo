import '../models/todo.dart';

const reminderLeadTime = Duration(minutes: 10);

DateTime reminderInstantFor(Todo todo) =>
    todo.dueAt!.toUtc().subtract(reminderLeadTime);

enum ReminderPermissionStatus {
  enabled,
  notificationsDenied,
  exactAlarmDenied,
  unavailable,
}

enum ReminderScheduleResult { scheduled, completed, undated, noAdvanceNotice }

class PendingReminder {
  const PendingReminder({required this.id, this.payload});

  final int id;
  final String? payload;
}

/// Platform reminder contract. Permission requests must only follow user action.
abstract interface class NotificationService {
  Future<void> initialize();
  Future<ReminderPermissionStatus> checkPermissionStatus();
  Future<ReminderPermissionStatus> requestPermissions();
  Future<ReminderScheduleResult> scheduleReminder(Todo todo);
  Future<void> cancelReminder(int notificationId);
  Future<List<PendingReminder>> pendingReminders();
}

import 'dart:async';

import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/services/local_notification_service.dart';
import 'package:focus_todo/services/notification_service.dart';
import 'package:timezone/timezone.dart' as timezone;

class MemoryNotificationService implements NotificationService {
  DateTime now = DateTime(2026, 10, 7, 12);
  ReminderPermissionStatus permissionStatus = ReminderPermissionStatus.enabled;
  ReminderPermissionStatus requestedStatus = ReminderPermissionStatus.enabled;
  bool failInitialize = false;
  bool failPendingRead = false;
  bool failSchedule = false;
  bool failCancel = false;
  int initializeCalls = 0;
  int permissionRequests = 0;
  final List<Todo> scheduledTodos = [];
  final List<int> cancelledIds = [];
  final Map<int, PendingReminder> pending = {};
  Completer<void>? scheduleGate;
  Completer<void>? scheduleStarted;
  Completer<void>? cancelGate;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (failInitialize) throw StateError('notification init failed');
  }

  @override
  Future<ReminderPermissionStatus> checkPermissionStatus() async =>
      permissionStatus;

  @override
  Future<ReminderPermissionStatus> requestPermissions() async {
    permissionRequests++;
    permissionStatus = requestedStatus;
    return permissionStatus;
  }

  @override
  Future<ReminderScheduleResult> scheduleReminder(Todo todo) async {
    scheduledTodos.add(todo);
    if (scheduleStarted != null && !scheduleStarted!.isCompleted) {
      scheduleStarted!.complete();
    }
    await scheduleGate?.future;
    if (failSchedule) throw StateError('schedule failed');
    if (todo.isCompleted) return ReminderScheduleResult.completed;
    if (todo.dueAt == null) return ReminderScheduleResult.undated;
    if (!reminderInstantFor(todo).isAfter(now.toUtc())) {
      return ReminderScheduleResult.noAdvanceNotice;
    }
    pending[todo.notificationId] = PendingReminder(
      id: todo.notificationId,
      payload: todo.id,
    );
    return ReminderScheduleResult.scheduled;
  }

  @override
  Future<void> cancelReminder(int notificationId) async {
    cancelledIds.add(notificationId);
    await cancelGate?.future;
    if (failCancel) throw StateError('cancel failed');
    pending.remove(notificationId);
  }

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    if (failPendingRead) throw StateError('pending read failed');
    return pending.values.toList();
  }
}

class MemoryReminderBackend implements ReminderNotificationBackend {
  ReminderPermissionStatus permissionStatus = ReminderPermissionStatus.enabled;
  ReminderPermissionStatus requestedStatus = ReminderPermissionStatus.enabled;
  bool failInitialize = false;
  bool failSchedule = false;
  int initializeCalls = 0;
  final Map<int, PendingReminder> pending = {};
  final List<({int id, timezone.TZDateTime scheduledDate, String payload})>
  schedules = [];

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (failInitialize) throw StateError('backend init failed');
  }

  @override
  Future<ReminderPermissionStatus> checkPermissionStatus() async =>
      permissionStatus;

  @override
  Future<ReminderPermissionStatus> requestPermissions() async =>
      permissionStatus = requestedStatus;

  @override
  Future<void> schedule({
    required int id,
    required timezone.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (failSchedule) throw StateError('backend schedule failed');
    schedules.add((id: id, scheduledDate: scheduledDate, payload: payload));
    pending[id] = PendingReminder(id: id, payload: payload);
  }

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
  }

  @override
  Future<List<PendingReminder>> pendingReminders() async =>
      pending.values.toList();
}

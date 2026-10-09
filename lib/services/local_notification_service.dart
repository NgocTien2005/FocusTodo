import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/todo.dart';
import 'notification_service.dart';

typedef ReminderClock = DateTime Function();
typedef DeviceTimezoneProvider = Future<String> Function();

abstract interface class ReminderNotificationBackend {
  Future<void> initialize();
  Future<ReminderPermissionStatus> checkPermissionStatus();
  Future<ReminderPermissionStatus> requestPermissions();
  Future<void> schedule({
    required int id,
    required timezone.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
  });
  Future<void> cancel(int id);
  Future<List<PendingReminder>> pendingReminders();
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService({
    ReminderNotificationBackend? backend,
    ReminderClock? clock,
    DeviceTimezoneProvider? timezoneProvider,
  }) : _backend = backend ?? FlutterLocalNotificationBackend(),
       _clock = clock ?? DateTime.now,
       _timezoneProvider = timezoneProvider ?? _deviceTimezone;

  final ReminderNotificationBackend _backend;
  final ReminderClock _clock;
  final DeviceTimezoneProvider _timezoneProvider;
  Future<void>? _initialization;

  static Future<String> _deviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  @override
  Future<void> initialize() {
    final current = _initialization;
    if (current != null) return current;
    final initializing = _initialize();
    _initialization = initializing;
    return initializing.catchError((Object error, StackTrace stack) {
      if (identical(_initialization, initializing)) _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final locationName = await _timezoneProvider();
    timezone.setLocalLocation(timezone.getLocation(locationName));
    await _backend.initialize();
  }

  @override
  Future<ReminderPermissionStatus> checkPermissionStatus() async {
    await initialize();
    return _backend.checkPermissionStatus();
  }

  @override
  Future<ReminderPermissionStatus> requestPermissions() async {
    await initialize();
    return _backend.requestPermissions();
  }

  @override
  Future<ReminderScheduleResult> scheduleReminder(Todo todo) async {
    if (todo.isCompleted) return ReminderScheduleResult.completed;
    final dueAt = todo.dueAt;
    if (dueAt == null) return ReminderScheduleResult.undated;
    final reminderAt = reminderInstantFor(todo);
    if (!reminderAt.isAfter(_clock().toUtc())) {
      return ReminderScheduleResult.noAdvanceNotice;
    }
    await initialize();
    final permission = await _backend.checkPermissionStatus();
    if (permission != ReminderPermissionStatus.enabled) {
      throw ReminderPermissionException(permission);
    }
    await _backend.schedule(
      id: todo.notificationId,
      scheduledDate: timezone.TZDateTime.from(reminderAt, timezone.local),
      title: 'TODO reminder',
      body: todo.title,
      payload: todo.id,
    );
    return ReminderScheduleResult.scheduled;
  }

  @override
  Future<void> cancelReminder(int notificationId) async {
    await initialize();
    await _backend.cancel(notificationId);
  }

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    await initialize();
    return _backend.pendingReminders();
  }
}

class ReminderPermissionException implements Exception {
  const ReminderPermissionException(this.status);
  final ReminderPermissionStatus status;
  @override
  String toString() => switch (status) {
    ReminderPermissionStatus.notificationsDenied =>
      'Notification permission is disabled.',
    ReminderPermissionStatus.exactAlarmDenied =>
      'Exact alarm access is disabled.',
    ReminderPermissionStatus.unavailable =>
      'Scheduled reminders are unavailable on this platform.',
    ReminderPermissionStatus.enabled => 'Reminder permission is enabled.',
  };
}

class FlutterLocalNotificationBackend implements ReminderNotificationBackend {
  FlutterLocalNotificationBackend({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'focus_todo_reminders';
  static const channelName = 'TODO reminders';
  static const channelDescription =
      'Reminders ten minutes before TODOs are due.';
  static const notificationIcon = 'ic_stat_focus_todo';
  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('TODO reminders are supported on Android only.');
    }
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize Android notifications.');
    }
    await _android!.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
        playSound: true,
      ),
    );
  }

  @override
  Future<ReminderPermissionStatus> checkPermissionStatus() async {
    if (!Platform.isAndroid) return ReminderPermissionStatus.unavailable;
    final android = _android!;
    if (await android.areNotificationsEnabled() != true) {
      return ReminderPermissionStatus.notificationsDenied;
    }
    if (await android.canScheduleExactNotifications() != true) {
      return ReminderPermissionStatus.exactAlarmDenied;
    }
    return ReminderPermissionStatus.enabled;
  }

  @override
  Future<ReminderPermissionStatus> requestPermissions() async {
    if (!Platform.isAndroid) return ReminderPermissionStatus.unavailable;
    final android = _android!;
    await android.requestNotificationsPermission();
    if (await android.areNotificationsEnabled() != true) {
      return ReminderPermissionStatus.notificationsDenied;
    }
    if (await android.canScheduleExactNotifications() != true) {
      await android.requestExactAlarmsPermission();
    }
    return checkPermissionStatus();
  }

  @override
  Future<void> schedule({
    required int id,
    required timezone.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        icon: notificationIcon,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: payload,
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<List<PendingReminder>> pendingReminders() async =>
      (await _plugin.pendingNotificationRequests())
          .map(
            (request) =>
                PendingReminder(id: request.id, payload: request.payload),
          )
          .toList(growable: false);
}

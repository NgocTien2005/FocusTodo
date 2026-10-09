import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/models/todo.dart';
import 'package:focus_todo/services/local_notification_service.dart';
import 'package:focus_todo/services/notification_service.dart';

import 'support/memory_notification_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  Todo todo({
    DateTime? dueAt,
    bool completed = false,
    int notificationId = 42,
  }) => Todo(
    id: 'todo-1',
    title: 'Prepare review',
    description: 'Keep notes',
    dueAt: dueAt,
    isCompleted: completed,
    createdAt: now,
    notificationId: notificationId,
  );

  test(
    'schedules exactly ten minutes before due and keeps the UTC instant',
    () async {
      final backend = MemoryReminderBackend();
      var timezoneReads = 0;
      final service = LocalNotificationService(
        backend: backend,
        clock: () => now,
        timezoneProvider: () async {
          timezoneReads++;
          return 'America/Los_Angeles';
        },
      );
      final due = DateTime.utc(2026, 10, 7, 12, 15);
      expect(
        await service.scheduleReminder(todo(dueAt: due)),
        ReminderScheduleResult.scheduled,
      );
      expect(backend.schedules, hasLength(1));
      final scheduled = backend.schedules.single;
      expect(scheduled.id, 42);
      expect(scheduled.payload, 'todo-1');
      expect(scheduled.scheduledDate.location.name, 'America/Los_Angeles');
      expect(scheduled.scheduledDate.toUtc(), DateTime.utc(2026, 10, 7, 12, 5));
      await service.initialize();
      expect(backend.initializeCalls, 1);
      expect(timezoneReads, 1);
    },
  );

  test(
    'completed, undated, and past reminder instants are never scheduled',
    () async {
      final backend = MemoryReminderBackend();
      final service = LocalNotificationService(
        backend: backend,
        clock: () => now,
        timezoneProvider: () async => 'UTC',
      );
      expect(
        await service.scheduleReminder(
          todo(dueAt: now.add(const Duration(hours: 1)), completed: true),
        ),
        ReminderScheduleResult.completed,
      );
      expect(
        await service.scheduleReminder(todo()),
        ReminderScheduleResult.undated,
      );
      expect(
        await service.scheduleReminder(
          todo(dueAt: now.add(const Duration(minutes: 9))),
        ),
        ReminderScheduleResult.noAdvanceNotice,
      );
      expect(
        await service.scheduleReminder(
          todo(dueAt: now.add(const Duration(minutes: 10))),
        ),
        ReminderScheduleResult.noAdvanceNotice,
      );
      expect(backend.schedules, isEmpty);
    },
  );

  test(
    'permission denial is explicit and initialization can be retried',
    () async {
      final deniedBackend = MemoryReminderBackend()
        ..permissionStatus = ReminderPermissionStatus.exactAlarmDenied
        ..requestedStatus = ReminderPermissionStatus.notificationsDenied;
      final deniedService = LocalNotificationService(
        backend: deniedBackend,
        clock: () => now,
        timezoneProvider: () async => 'UTC',
      );
      expect(
        await deniedService.checkPermissionStatus(),
        ReminderPermissionStatus.exactAlarmDenied,
      );
      expect(
        await deniedService.requestPermissions(),
        ReminderPermissionStatus.notificationsDenied,
      );
      await expectLater(
        deniedService.scheduleReminder(
          todo(dueAt: now.add(const Duration(hours: 1))),
        ),
        throwsA(isA<ReminderPermissionException>()),
      );

      final retryBackend = MemoryReminderBackend()..failInitialize = true;
      final retryService = LocalNotificationService(
        backend: retryBackend,
        clock: () => now,
        timezoneProvider: () async => 'UTC',
      );
      await expectLater(retryService.initialize(), throwsStateError);
      retryBackend.failInitialize = false;
      await retryService.initialize();
      expect(retryBackend.initializeCalls, 2);
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_todo/models/todo.dart';

void main() {
  final todo = Todo(
    id: 'todo-1',
    title: 'Study',
    description: 'Review notes',
    dueAt: DateTime.utc(2026, 10, 11, 9),
    createdAt: DateTime.utc(2026, 10, 7),
    notificationId: 42,
  );

  test('JSON round trip preserves fields and stable notification ID', () {
    final restored = Todo.fromJson(
      jsonDecode(jsonEncode(todo.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), todo.toJson());
    expect(restored.notificationId, 42);
    expect(restored.isCompleted, isFalse);
  });

  test('undated TODO and nullable description survive JSON round trip', () {
    final undated = todo.copyWith(dueAt: null, description: null);
    final restored = Todo.fromJson(
      jsonDecode(jsonEncode(undated.toJson())) as Map<String, dynamic>,
    );
    expect(restored.dueAt, isNull);
    expect(restored.description, isNull);
    expect(restored.createdAt, todo.createdAt);
  });

  test(
    'copyWith preserves omitted fields and does not mutate the original',
    () {
      final completed = todo.copyWith(isCompleted: true, title: 'Reviewed');
      expect(completed.dueAt, todo.dueAt);
      expect(completed.description, todo.description);
      expect(completed.notificationId, todo.notificationId);
      expect(completed.isCompleted, isTrue);
      expect(todo.isCompleted, isFalse);
      expect(todo.title, 'Study');
    },
  );

  test('JSON rejects notification IDs outside Android int32 range', () {
    expect(
      () => Todo.fromJson({...todo.toJson(), 'notificationId': -1}),
      throwsFormatException,
    );
    expect(
      () => Todo.fromJson({...todo.toJson(), 'notificationId': 2147483648}),
      throwsFormatException,
    );
  });
}

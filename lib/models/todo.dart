import 'package:flutter/foundation.dart';

const _unchanged = Object();

/// Dates serialize as UTC instants; category filtering must convert to local time.
@immutable
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.description,
    this.dueAt,
    this.isCompleted = false,
    required this.createdAt,
    required this.notificationId,
  }) : assert(notificationId >= 0 && notificationId <= 2147483647);

  final String id;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final bool isCompleted;
  final DateTime createdAt;
  final int notificationId;

  /// Omit nullable fields to preserve them; pass null to explicitly clear them.
  Todo copyWith({
    String? id,
    String? title,
    Object? description = _unchanged,
    Object? dueAt = _unchanged,
    bool? isCompleted,
    DateTime? createdAt,
    int? notificationId,
  }) => Todo(
    id: id ?? this.id,
    title: title ?? this.title,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    dueAt: identical(dueAt, _unchanged) ? this.dueAt : dueAt as DateTime?,
    isCompleted: isCompleted ?? this.isCompleted,
    createdAt: createdAt ?? this.createdAt,
    notificationId: notificationId ?? this.notificationId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'isCompleted': isCompleted,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'notificationId': notificationId,
  };

  factory Todo.fromJson(Map<String, dynamic> json) {
    final notificationId = json['notificationId'] as int;
    if (notificationId < 0 || notificationId > 2147483647) {
      throw const FormatException('notificationId must be a nonnegative int32');
    }
    return Todo(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      dueAt: json['dueAt'] == null
          ? null
          : DateTime.parse(json['dueAt'] as String),
      isCompleted: json['isCompleted'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      notificationId: notificationId,
    );
  }
}

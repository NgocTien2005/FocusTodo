import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/todo_controller.dart';
import '../models/todo.dart';
import '../services/notification_service.dart';
import '../widgets/empty_state.dart';
import 'create_todo_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _search;

  Future<void> _confirmDelete(TodoController controller, Todo todo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete TODO?'),
        content: Text('Delete “${todo.title}”? This cannot be undone.'),
        actions: [
          TextButton(
            key: const Key('cancel-delete'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.deleteTodo(todo.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Deleted “${todo.title}”.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Could not delete TODO: $error')),
          );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: context.read<TodoController>().searchQuery,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final controller = context.read<TodoController>();
      controller.refreshDateSensitiveResults();
      unawaited(controller.onAppResumed());
    }
  }

  Widget _reminderBanner(TodoController controller) {
    final children = <Widget>[];
    final permission = controller.reminderPermissionStatus;
    if (controller.reminderInitializationError != null) {
      children.add(const Text('Reminders could not be initialized.'));
      children.add(
        Text(
          controller.reminderInitializationError!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
      children.add(
        TextButton(
          onPressed: controller.isReconcilingReminders
              ? null
              : controller.retryReminderReconciliation,
          child: const Text('Retry reminders'),
        ),
      );
    } else if (permission == ReminderPermissionStatus.notificationsDenied ||
        permission == ReminderPermissionStatus.exactAlarmDenied) {
      children.add(
        Text(
          permission == ReminderPermissionStatus.notificationsDenied
              ? 'Notifications are disabled. Enable them to receive TODO reminders.'
              : 'Exact alarm access is disabled. Reminders cannot be scheduled precisely.',
        ),
      );
      children.add(
        TextButton.icon(
          onPressed: controller.isRequestingReminderPermissions
              ? null
              : controller.requestReminderPermissions,
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(
            controller.isRequestingReminderPermissions
                ? 'Checking permissions…'
                : 'Enable reminders',
          ),
        ),
      );
    } else if (permission == ReminderPermissionStatus.unavailable) {
      children.add(const Text('Scheduled reminders are available on Android.'));
    }
    if (controller.reminderReconciliationError != null) {
      children.add(const Text('Some reminders could not be synchronized.'));
      children.add(
        TextButton(
          onPressed: controller.isReconcilingReminders
              ? null
              : controller.retryReminderReconciliation,
          child: const Text('Retry synchronization'),
        ),
      );
    }
    for (final entry in controller.reminderScheduleErrors.entries) {
      children.add(
        Row(
          children: [
            Expanded(
              child: Text(
                'TODO saved, but reminder could not be scheduled (${entry.key}).',
              ),
            ),
            TextButton(
              onPressed: () => controller.retryScheduleReminder(entry.key),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    for (final warning in controller.reminderCancellationWarnings) {
      children.add(
        Row(
          children: [
            Expanded(
              child: Text('Could not cancel reminder for ${warning.title}.'),
            ),
            TextButton(
              onPressed: () => controller.retryCancellation(warning),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Widget _content(TodoController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadError != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load TODOs'),
              const SizedBox(height: 8),
              Text(controller.loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.loadTodos,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final todos = controller.visibleTodos;
    if (todos.isEmpty) {
      return EmptyState(
        message: controller.activeTodos.isEmpty
            ? 'No active TODOs.'
            : controller.hasSearchQuery
            ? 'No matching TODOs in this category.'
            : 'No TODOs in this category.',
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: todos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final todo = todos[index];
        final due = todo.dueAt?.toLocal();
        return Card(
          key: ValueKey(todo.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        todo.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (controller.isCompleting(todo.id) ||
                        controller.isDeleting(todo.id))
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Semantics(
                        label: 'Complete ${todo.title}',
                        child: Checkbox(
                          key: ValueKey('complete-${todo.id}'),
                          value: false,
                          onChanged:
                              controller.isEditing(todo.id) ||
                                  controller.isDeleting(todo.id)
                              ? null
                              : (value) async {
                                  if (value != true) return;
                                  try {
                                    await controller.completeTodo(todo.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Completed “${todo.title}”.',
                                            ),
                                          ),
                                        );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Could not complete TODO: $error',
                                            ),
                                          ),
                                        );
                                    }
                                  }
                                },
                        ),
                      ),
                  ],
                ),
                if (todo.description != null &&
                    todo.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(todo.description!),
                ],
                const SizedBox(height: 8),
                Text(
                  due == null
                      ? 'No due date or time'
                      : 'Due ${DateFormat.yMMMd().add_jm().format(due)}',
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    key: ValueKey('edit-${todo.id}'),
                    onPressed:
                        controller.isEditing(todo.id) ||
                            controller.isDeleting(todo.id) ||
                            controller.isCompleting(todo.id)
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CreateTodoScreen(todo: todo),
                              ),
                            );
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      controller.isEditing(todo.id) ? 'Saving…' : 'Edit',
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    key: ValueKey('delete-${todo.id}'),
                    onPressed:
                        controller.isDeleting(todo.id) ||
                            controller.isEditing(todo.id) ||
                            controller.isCompleting(todo.id)
                        ? null
                        : () => _confirmDelete(controller, todo),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      controller.isDeleting(todo.id) ? 'Deleting…' : 'Delete',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TodoController>();
    return Scaffold(
      appBar: AppBar(title: const Text('FocusTodo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TodoCategory>(
                segments: const [
                  ButtonSegment(value: TodoCategory.all, label: Text('All')),
                  ButtonSegment(
                    value: TodoCategory.today,
                    label: Text('Today'),
                  ),
                  ButtonSegment(
                    value: TodoCategory.upcoming,
                    label: Text('Upcoming'),
                  ),
                ],
                selected: {controller.category},
                onSelectionChanged: (values) =>
                    controller.selectCategory(values.single),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('todo-search'),
                controller: _search,
                onChanged: controller.setSearchQuery,
                decoration: InputDecoration(
                  labelText: 'Search TODOs',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            controller.setSearchQuery('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              _reminderBanner(controller),
              Expanded(child: _content(controller)),
              FilledButton.icon(
                onPressed: controller.canCreate
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CreateTodoScreen(),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add TODO'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

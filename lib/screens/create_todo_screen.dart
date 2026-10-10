import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/todo_controller.dart';
import '../models/todo.dart';
import '../services/notification_service.dart';

class CreateTodoScreen extends StatefulWidget {
  const CreateTodoScreen({super.key, this.todo});

  final Todo? todo;

  @override
  State<CreateTodoScreen> createState() => _CreateTodoScreenState();
}

class _CreateTodoScreenState extends State<CreateTodoScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _dueTimeChanged = false;
  String? _dueError;
  String? _saveError;
  String? _savedTodoId;
  String? _reminderError;
  bool _noAdvanceNotice = false;
  ReminderCancellationWarning? _cancellationWarning;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final todo = widget.todo;
    if (todo == null) return;
    _title.text = todo.title;
    _description.text = todo.description ?? '';
    final due = todo.dueAt?.toLocal();
    if (due != null) {
      _date = DateTime(due.year, due.month, due.day);
      _time = TimeOfDay.fromDateTime(due);
    }
  }

  Future<void> _pickDate() async {
    final now = context.read<TodoController>().currentTime.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 100, 12, 31);
    var initial = _date ?? today;
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDate,
    );
    if (!mounted || result == null) return;
    setState(() {
      _date = result;
      _dueTimeChanged = true;
      _dueError = null;
    });
  }

  Future<void> _pickTime() async {
    final now = context.read<TodoController>().currentTime.toLocal();
    final result = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(now),
    );
    if (!mounted || result == null) return;
    setState(() {
      _time = result;
      _dueTimeChanged = true;
      _dueError = null;
    });
  }

  Future<void> _submit() async {
    final controller = context.read<TodoController>();
    if (_submitting || controller.isSaving || _savedTodoId != null) return;
    final validTitle = _form.currentState!.validate();
    DateTime? dueAt;
    String? dueError;
    if (widget.todo != null && !_dueTimeChanged) {
      // Keep the exact stored instant, including seconds, when editing only
      // title/description. This also allows metadata edits on overdue TODOs.
      dueAt = widget.todo!.dueAt;
    } else if ((_date == null) != (_time == null)) {
      dueError = 'Choose both a date and a time, or clear the due time.';
    } else if (_date != null && _time != null) {
      dueAt = DateTime(
        _date!.year,
        _date!.month,
        _date!.day,
        _time!.hour,
        _time!.minute,
      );
      // Reject normalized nonexistent local times during a DST clock change.
      if (dueAt.year != _date!.year ||
          dueAt.month != _date!.month ||
          dueAt.day != _date!.day ||
          dueAt.hour != _time!.hour ||
          dueAt.minute != _time!.minute) {
        dueError = 'This local date/time does not exist. Choose another time.';
      } else {
        if (widget.todo == null || _dueTimeChanged) {
          dueError = TodoController.validateDueAt(
            dueAt,
            controller.currentTime,
          );
        }
      }
    }
    setState(() {
      _dueError = dueError;
      _saveError = null;
      _reminderError = null;
    });
    if (!validTitle || dueError != null) return;
    setState(() => _submitting = true);
    try {
      final saved = widget.todo == null
          ? await controller.createTodo(
              title: _title.text,
              description: _description.text,
              dueAt: dueAt,
            )
          : await controller.updateTodo(
              id: widget.todo!.id,
              title: _title.text,
              description: _description.text,
              dueAt: dueAt,
              dueTimeChanged: _dueTimeChanged,
            );
      if (!mounted) return;
      final reminderError = controller.reminderScheduleError(saved.id);
      final cancellationWarning = controller.reminderCancellationWarningForTodo(
        saved.id,
      );
      final noAdvanceNotice = controller.reminderHasNoAdvanceNotice(saved.id);
      if (reminderError != null ||
          cancellationWarning != null ||
          noAdvanceNotice) {
        setState(() {
          _savedTodoId = saved.id;
          _reminderError = reminderError;
          _cancellationWarning = cancellationWarning;
          _noAdvanceNotice = noAdvanceNotice;
        });
        return;
      }
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _retryReminder() async {
    final todoId = _savedTodoId;
    if (todoId == null || _submitting) return;
    final controller = context.read<TodoController>();
    setState(() => _submitting = true);
    try {
      final warning = controller.reminderCancellationWarningForTodo(todoId);
      if (warning != null) {
        await controller.retryCancellation(warning);
      } else if (controller.reminderPermissionStatus !=
          ReminderPermissionStatus.enabled) {
        await controller.requestReminderPermissions();
      } else {
        await controller.retryScheduleReminder(todoId);
      }
      if (!mounted) return;
      final error = controller.reminderScheduleError(todoId);
      final cancellationWarning = controller.reminderCancellationWarningForTodo(
        todoId,
      );
      final noAdvanceNotice = controller.reminderHasNoAdvanceNotice(todoId);
      if (error == null && cancellationWarning == null && !noAdvanceNotice) {
        FocusScope.of(context).unfocus();
        Navigator.of(context).pop();
      } else {
        setState(() {
          _reminderError = error;
          _cancellationWarning = cancellationWarning;
          _noAdvanceNotice = noAdvanceNotice;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _reminderError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<TodoController>().isSaving || _submitting;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.todo == null ? 'Create TODO' : 'Edit TODO'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('todo-title'),
                    controller: _title,
                    enabled: !saving && _savedTodoId == null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        TodoController.validateTitle(value ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'Title (required)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('todo-description'),
                    controller: _description,
                    enabled: !saving && _savedTodoId == null,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Due date and time (optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('pick-date'),
                    onPressed: saving || _savedTodoId != null
                        ? null
                        : _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _date == null
                          ? 'Choose date'
                          : DateFormat.yMMMd().format(_date!),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('pick-time'),
                    onPressed: saving || _savedTodoId != null
                        ? null
                        : _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _time == null ? 'Choose time' : _time!.format(context),
                    ),
                  ),
                  if (_date != null || _time != null)
                    TextButton(
                      onPressed: saving || _savedTodoId != null
                          ? null
                          : () => setState(() {
                              _date = null;
                              _time = null;
                              _dueError = null;
                            }),
                      child: const Text('Clear due time'),
                    )
                  else
                    const Text('No due time means no reminder.'),
                  if (_dueError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dueError!,
                      key: const Key('due-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_savedTodoId != null) ...[
                    const SizedBox(height: 16),
                    if (_reminderError != null) ...[
                      const Text(
                        'TODO saved, but reminder could not be scheduled.',
                        key: Key('reminder-save-warning'),
                      ),
                      Text(
                        _reminderError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      FilledButton.tonal(
                        key: const Key('retry-reminder'),
                        onPressed: saving ? null : _retryReminder,
                        child: const Text('Retry reminder'),
                      ),
                    ] else if (_cancellationWarning != null) ...[
                      const Text(
                        'TODO saved, but its reminder could not be updated.',
                        key: Key('reminder-update-warning'),
                      ),
                      Text(
                        _cancellationWarning!.error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      FilledButton.tonal(
                        key: const Key('retry-reminder'),
                        onPressed: saving ? null : _retryReminder,
                        child: const Text('Retry reminder update'),
                      ),
                    ] else if (_noAdvanceNotice)
                      const Text(
                        'TODO saved. A full 10-minute advance reminder is unavailable because it is due too soon.',
                        key: Key('no-advance-reminder'),
                      ),
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Back to TODOs'),
                    ),
                  ],
                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _saveError!,
                      key: const Key('save-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_savedTodoId == null)
                    FilledButton(
                      key: const Key('save-todo'),
                      onPressed: saving ? null : _submit,
                      child: Text(
                        saving
                            ? 'Saving…'
                            : widget.todo == null
                            ? 'Save TODO'
                            : 'Save changes',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/todo_controller.dart';

class CreateTodoScreen extends StatefulWidget {
  const CreateTodoScreen({super.key});

  @override
  State<CreateTodoScreen> createState() => _CreateTodoScreenState();
}

class _CreateTodoScreenState extends State<CreateTodoScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  String? _dueError;
  String? _saveError;
  bool _submitting = false;

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
      _dueError = null;
    });
  }

  Future<void> _submit() async {
    final controller = context.read<TodoController>();
    if (_submitting || controller.isSaving) return;
    final validTitle = _form.currentState!.validate();
    DateTime? dueAt;
    String? dueError;
    if ((_date == null) != (_time == null)) {
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
        dueError = TodoController.validateDueAt(dueAt, controller.currentTime);
      }
    }
    setState(() {
      _dueError = dueError;
      _saveError = null;
    });
    if (!validTitle || dueError != null) return;
    setState(() => _submitting = true);
    try {
      await controller.createTodo(
        title: _title.text,
        description: _description.text,
        dueAt: dueAt,
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = error.toString());
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
        appBar: AppBar(title: const Text('Create TODO')),
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
                    enabled: !saving,
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
                    enabled: !saving,
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
                    onPressed: saving ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _date == null
                          ? 'Choose date'
                          : DateFormat.yMMMd().format(_date!),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('pick-time'),
                    onPressed: saving ? null : _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _time == null ? 'Choose time' : _time!.format(context),
                    ),
                  ),
                  if (_date != null || _time != null)
                    TextButton(
                      onPressed: saving
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
                  const SizedBox(height: 16),
                  const Text('Reminder scheduling is coming next.'),
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
                  FilledButton(
                    key: const Key('save-todo'),
                    onPressed: saving ? null : _submit,
                    child: Text(saving ? 'Saving…' : 'Save TODO'),
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

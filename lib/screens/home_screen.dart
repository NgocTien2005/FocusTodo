import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/todo_controller.dart';
import '../widgets/empty_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _comingNext(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Coming next: $feature.')));
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
                readOnly: true,
                onTap: () => _comingNext(context, 'search TODOs'),
                decoration: const InputDecoration(
                  labelText: 'Search TODOs',
                  helperText: 'Coming next',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const Expanded(child: EmptyState()),
              FilledButton.icon(
                onPressed: () =>
                    _comingNext(context, 'add a TODO with a date and time'),
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

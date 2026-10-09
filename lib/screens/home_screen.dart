import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controllers/todo_controller.dart';
import '../widgets/empty_state.dart';
import 'create_todo_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _search;

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
      context.read<TodoController>().refreshDateSensitiveResults();
    }
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
                    if (controller.isCompleting(todo.id))
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
                          onChanged: (value) async {
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

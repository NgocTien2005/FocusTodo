import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/todo_controller.dart';
import 'repositories/shared_preferences_todo_repository.dart';
import 'repositories/todo_repository.dart';
import 'screens/home_screen.dart';

class FocusTodoApp extends StatelessWidget {
  const FocusTodoApp({super.key, this.repository, this.clock});

  final TodoRepository? repository;
  final TodoClock? clock;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TodoController(
      repository: repository ?? SharedPreferencesTodoRepository(),
      clock: clock,
    )..loadTodos(),
    child: MaterialApp(
      title: 'FocusTodo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const HomeScreen(),
    ),
  );
}

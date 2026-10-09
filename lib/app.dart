import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/todo_controller.dart';
import 'repositories/shared_preferences_todo_repository.dart';
import 'repositories/todo_repository.dart';
import 'screens/home_screen.dart';
import 'services/local_notification_service.dart';
import 'services/notification_service.dart';

class FocusTodoApp extends StatelessWidget {
  const FocusTodoApp({
    super.key,
    this.repository,
    this.notificationService,
    this.clock,
  });

  final TodoRepository? repository;
  final NotificationService? notificationService;
  final TodoClock? clock;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TodoController(
      repository: repository ?? SharedPreferencesTodoRepository(),
      notificationService:
          notificationService ?? LocalNotificationService(clock: clock),
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

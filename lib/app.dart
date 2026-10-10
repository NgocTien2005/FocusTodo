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
  Widget build(BuildContext context) {
    const seed = Color(0xFF3D7668);
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ChangeNotifierProvider(
      create: (_) => TodoController(
        repository: repository ?? SharedPreferencesTodoRepository(),
        notificationService:
            notificationService ?? LocalNotificationService(clock: clock),
        clock: clock,
      )..loadTodos(),
      child: MaterialApp(
        title: 'FocusTodo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: scheme.surface,
          cardTheme: CardThemeData(
            color: scheme.surfaceContainerLow,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

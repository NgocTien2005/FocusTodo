import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/todo_controller.dart';
import 'screens/home_screen.dart';

class FocusTodoApp extends StatelessWidget {
  const FocusTodoApp({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TodoController(),
    child: MaterialApp(
      title: 'FocusTodo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const HomeScreen(),
    ),
  );
}
